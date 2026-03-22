# gotools.sh

A script to manage Go build tools (like `golangci-lint`, `task`, or `mockgen`) using Go 1.24+ `tool` directives.

`gotools.sh` isolates each tool into its own `.mod` file within a `tools/` directory. This prevents tool dependencies from polluting your main `go.mod` and avoids version conflicts between the tools themselves.

## Features

* **Two Strategies:** Choose between `workspace` (single shared `go.mod`) or `isolated` (one `.mod` per tool).
* **Go Version Parity:** Tool environments automatically sync to the Go version defined in your project's root `go.mod`.
* **Reproducibility:** Committing the `tools/` directory guarantees the exact same tool versions are used locally and in CI.
* **Smart Install:** Automatically infers the tool name from the package path.
* **Self-Update:** Update `gotools.sh` itself with a single command.

## Requirements

* Go 1.24 or higher
* Bash

## Installation

### Option 1: Global install (recommended)

Run the installer to download `gotools.sh` into your Go bin directory (`GOBIN`, `GOPATH/bin`, or `~/go/bin`). This makes `gotools.sh` available system-wide, just like any other Go tool.

**Install the latest release:**

```bash
curl -fsSL https://raw.githubusercontent.com/piusalfred/gotools.sh/main/install.sh | bash
```

**Install a specific version:**

Set the `VERSION` environment variable to a release tag. Both `v0.0.10` and `0.0.10` are accepted:

```bash
curl -fsSL https://raw.githubusercontent.com/piusalfred/gotools.sh/main/install.sh | VERSION=v0.0.10 bash
```

When `VERSION` is omitted or set to `latest`, the installer queries the [GitHub Releases API](https://github.com/piusalfred/gotools.sh/releases) to resolve the most recent tag. If the API is unreachable it falls back to the `main` branch.

> **Note:** Make sure your Go bin directory is in your `PATH`. The installer will warn you if it isn't.

### Option 2: Per-project vendored script

Download the script directly into your repository (e.g., into a `scripts/` directory) and make it executable. This is useful when you want to pin the exact script version alongside your source code.

**Latest (from main branch):**

```bash
curl -fsSL https://raw.githubusercontent.com/piusalfred/gotools.sh/main/gotools.sh -o gotools.sh
chmod +x gotools.sh
```

**Specific version:**

Replace the branch name with a release tag:

```bash
curl -fsSL https://raw.githubusercontent.com/piusalfred/gotools.sh/v0.0.10/gotools.sh -o gotools.sh
chmod +x gotools.sh
```

Browse all available versions on the [releases page](https://github.com/piusalfred/gotools.sh/releases).

## Quick Start

```bash
# Bootstrap with isolated strategy (one .mod per tool)
./gotools.sh init --strategy=isolated

# Install a tool
./gotools.sh install github.com/google/addlicense

# Run it
./gotools.sh exec addlicense -l mit -c "Your Name" .
```

## Usage

| Command | Description |
| :--- | :--- |
| `init [flags]` | Bootstrap the project. Creates a `.gotools.env` config file. |
| `install [name] <pkg>` | Install a new tool. If `name` is omitted, it is inferred from the package path. Version defaults to `@latest`. |
| `exec <name> [args]` | Run a tool within its managed module context. |
| `sync` | Force state to match `.gotools.env` and the project Go version. |
| `upgrade <name> \| all` | Upgrade a specific tool, or all tools, to `@latest`. |
| `list` | Display all managed tools, their strategies, and package paths. |
| `remove <name...>` | Remove tools and their mod/sum files. |
| `version` | Print the current `gotools.sh` version. |
| `self-update` | Update `gotools.sh` itself to the latest release. |

### `init` Flags

| Flag | Default | Description |
| :--- | :--- | :--- |
| `--strategy=` | `workspace` | `workspace` (shared `go.mod`) or `isolated` (one `.mod` per tool). |
| `--dir=` | `tools` | Directory where tool module files are stored. |
| `--go=` | `inherit` | Go version for tool modules. `inherit` reads from the project root `go.mod`. |
| `--work=` | `true` | Whether to create/update a `go.work` file (workspace strategy only). |

### Examples

**Bootstrap a project:**
```bash
# Workspace strategy (default): all tools in a single tools/go.mod
./gotools.sh init

# Isolated strategy: each tool gets its own .mod file
./gotools.sh init --strategy=isolated

# Custom directory and explicit Go version
./gotools.sh init --strategy=isolated --dir=.build-tools --go=1.24
```

**Install tools:**
```bash
# Inferred name from package path
./gotools.sh install github.com/google/addlicense

# Explicit name
./gotools.sh install task github.com/go-task/task/v3/cmd/task
```

**Execute a tool:**
```bash
./gotools.sh exec addlicense -check .
```

**Keep tools updated and synced:**
```bash
# Upgrade all tools to their latest versions
./gotools.sh upgrade all

# Upgrade a single tool
./gotools.sh upgrade addlicense

# Sync tool Go versions after updating your root go.mod
./gotools.sh sync
```

**Version and self-update:**
```bash
# Print the current version
./gotools.sh version

# Update gotools.sh to the latest release
./gotools.sh self-update
```

## Configuration

Running `init` creates a `.gotools.env` file in the project root:

```bash
GOTOOLS_STRATEGY=isolated
GOTOOLS_DIR=tools
GOTOOLS_GO_VERSION=inherit
GOTOOLS_USE_WORK=true
```

All subsequent commands read this file automatically. You can edit it by hand or re-run `init` with different flags.

| Variable | Description |
| :--- | :--- |
| `GOTOOLS_STRATEGY` | `workspace` or `isolated`. |
| `GOTOOLS_DIR` | Path to the directory that holds tool module files. |
| `GOTOOLS_GO_VERSION` | Explicit Go version, or `inherit` to read from `go.mod`. |
| `GOTOOLS_USE_WORK` | If `true`, the workspace strategy creates a `go.work` file. |

## Strategies

### Workspace (`--strategy=workspace`)

All tools are tracked in a single `tools/go.mod` using Go 1.24+ `tool` directives. A `go.work` file is created to link the tools module to your project.

**Pros:** Simpler setup, fewer files.
**Cons:** Tool dependency trees can conflict with each other.

### Isolated (`--strategy=isolated`)

Each tool gets its own `<name>.mod` and `<name>.sum` file inside the tools directory. Tools are completely independent of each other.

**Pros:** Zero chance of dependency conflicts between tools.
**Cons:** More files to manage.

## CI Integration

Commit the generated tool files (`tools/*.mod`, `tools/*.sum`, or `tools/go.mod`) and `.gotools.env` to version control. This guarantees your CI pipeline uses the exact same tool versions as your local environment.

```yaml
- name: Sync tools
  run: ./gotools.sh sync

- name: Run linter
  run: ./gotools.sh exec golangci-lint run ./...

- name: Check license headers
  run: ./gotools.sh exec addlicense -check .
```
