#!/usr/bin/env bash
# Copyright (c) 2026 Pius Alfred
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -euo pipefail
TOOLS_DIR="${TOOLS_DIR:-$PWD/tools}"

# Ensure the tools directory exists
mkdir -p "$TOOLS_DIR"

# Resolve absolute path to ensure stability during 'cd' operations
TOOLS_DIR=$(cd "$TOOLS_DIR" && pwd)

# The base module path used for the isolated tool mod files
DEFAULT_MODULE="github.com/piusalfred/gotools/tools"

usage() {
    cat <<EOF
🧰 Go Tool Manager (Hermetic & Isolated)

Usage: $(basename "$0") <command> [arguments]

Commands:
  install [name] <pkg> [ver]    Install a new tool. If name is omitted, it is
                                inferred from the package path. Defaults to @latest.
  sync                          Sync all tools to the project's Go version and download deps.
  upgrade <name1> [name2...]    Update specific tools to @latest. Use 'all' for everything.
  exec    <name> [args...]      Run a managed tool.
  list                          List tools, pinned versions, and Go versions.
  remove  <name1> [name2...]    Remove tool .mod and .sum files.

Examples:
  ./gotools.sh install github.com/google/addlicense
  ./gotools.sh install task github.com/go-task/task/v3/cmd/task v3.35.0
  ./gotools.sh upgrade all
  ./gotools.sh exec task --version
EOF
    exit 1
}

get_default_name() {
    local pkg="$1"
    basename "$pkg"
}

resolve_go_version() {
    local root_mod="${TOOLS_DIR}/../go.mod"
    # Fallback if tools/ is the root or go.mod isn't in parent
    [[ ! -f "$root_mod" ]] && root_mod="${TOOLS_DIR}/go.mod"

    if [[ -f "$root_mod" ]]; then
        local v; v=$(awk '$1 == "go" { print $2; exit }' "$root_mod")
        [[ -n "$v" ]] && { echo "$v"; return; }
    fi
    # Fallback to system Go version (e.g., 1.26)
    go env GOVERSION | sed 's/go//' | awk -F. '{ print $1"."$2 }'
}

extract_tool_package() {
    awk '$1 == "tool" { if ($3 == "") print $2; else print $3; exit }' "$1"
}

extract_version() {
    local mod_file="$1"
    local base_mod; base_mod=$(basename "$mod_file")
    (cd "$TOOLS_DIR" && go list -m -modfile="$base_mod" -f '{{if not .Main}}{{.Version}}{{end}}' all | head -n 1) 2>/dev/null || echo "pinned"
}

# --- Command Implementations ---

cmd_install() {
    local tool_name=""
    local package=""
    local version="latest"

    # Smart Argument Parsing for DevEx
    if [[ $# -eq 1 ]]; then
        # Case: ./gotools.sh install <package>
        package="$1"
        tool_name=$(get_default_name "$package")
    elif [[ $# -eq 2 ]]; then
        # Case: ./gotools.sh install <name> <package>
        tool_name="$1"
        package="$2"
    elif [[ $# -ge 3 ]]; then
        # Case: ./gotools.sh install <name> <package> <version>
        tool_name="$1"
        package="$2"
        version="$3"
    else
        usage
    fi

    [[ "$version" != "latest" && "$version" != v* ]] && version="v$version"

    local mod_file="${TOOLS_DIR}/${tool_name}.mod"
    [[ -f "$mod_file" ]] && { echo "⚠️  ${tool_name}.mod already exists. Skipping..." ; return; }

    local go_ver; go_ver="$(resolve_go_version)"

    echo "📦 Installing ${tool_name} from ${package}@${version} (Go ${go_ver})..."

    # Create the isolated mod file
    cat > "$mod_file" <<MOD
module ${DEFAULT_MODULE}/${tool_name}

go ${go_ver}
MOD

    # Use Go 1.24+ native tool tracking
    (cd "$TOOLS_DIR" && go get -tool -modfile="${tool_name}.mod" "${package}@${version}")
    echo "✅ Success. Files created in ${TOOLS_DIR}"
}

cmd_sync() {
    local target_v; target_v="$(resolve_go_version)"
    echo "🔄 Syncing all tools to project Go version: ${target_v}"
    local count=0
    for f in "${TOOLS_DIR}"/*.mod; do
        [[ ! -f "$f" || "$(basename "$f")" == "go.mod" ]] && continue
        local base; base="$(basename "$f")"
        echo "  - Syncing ${base%.mod}..."
        (cd "$TOOLS_DIR" && go mod edit -go="${target_v}" -modfile="$base")
        (cd "$TOOLS_DIR" && go mod download -modfile="$base")
        count=$((count + 1))
    done
    echo "✅ Sync complete. Updated $count tools."
}

cmd_upgrade() {
    if [[ $# -eq 0 ]]; then
        echo "❌ Error: Provide tool names or 'all'." >&2
        return 1
    fi

    local tools_to_upgrade=()
    if [[ "$1" == "all" ]]; then
        for f in "${TOOLS_DIR}"/*.mod; do
            [[ ! -f "$f" || "$(basename "$f")" == "go.mod" ]] && continue
            tools_to_upgrade+=("$(basename "$f" .mod)")
        done
    else
        tools_to_upgrade=("$@")
    fi

    for tool in "${tools_to_upgrade[@]}"; do
        local mod_file="${TOOLS_DIR}/${tool}.mod"
        if [[ ! -f "$mod_file" ]]; then
            echo "⚠️  Tool '${tool}' not found. Skipping..."
            continue
        fi

        local pkg; pkg=$(extract_tool_package "$mod_file")
        echo "🚀 Upgrading ${tool} to latest..."
        (cd "$TOOLS_DIR" && go get -tool -modfile="${tool}.mod" "${pkg}@latest")
    done
    echo "✨ Upgrade process finished."
}

cmd_exec() {
    local tool_name="${1:?tool-name is required}"
    shift
    local mod_file="${TOOLS_DIR}/${tool_name}.mod"
    [[ ! -f "$mod_file" ]] && { echo "❌ Error: Tool '${tool_name}' not found. Run 'install' first." >&2; exit 1; }

    # Run tool using its isolated modfile context
    exec go tool -modfile="$mod_file" "$tool_name" "$@"
}

cmd_list() {
    printf "  %-20s %-15s %-8s %s\n" "TOOL" "VERSION" "GO VER" "PACKAGE PATH"
    printf "  %-20s %-15s %-8s %s\n" "----" "-------" "------" "------------"
    local found=0
    for f in "${TOOLS_DIR}"/*.mod; do
        [[ ! -f "$f" || "$(basename "$f")" == "go.mod" ]] && continue
        local name; name=$(basename "$f" .mod)
        local pkg; pkg=$(extract_tool_package "$f")
        local ver; ver=$(extract_version "$f")
        local gv; gv=$(awk '$1 == "go" {print $2}' "$f")
        printf "  %-20s %-15s %-8s %s\n" "$name" "$ver" "$gv" "$pkg"
        found=1
    done
    [[ $found -eq 0 ]] && echo "  (No tools managed yet)"
}


[[ $# -lt 1 ]] && usage
command="$1"; shift

case "$command" in
    install) cmd_install "$@" ;;
    sync)    cmd_sync ;;
    upgrade) cmd_upgrade "$@" ;;
    update)  cmd_upgrade "$@" ;;
    exec)    cmd_exec "$@" ;;
    list)    cmd_list ;;
    remove)
        for t in "$@"; do
            rm -f "${TOOLS_DIR}/${t}.mod" "${TOOLS_DIR}/${t}.sum"
            echo "🗑️  Removed ${t}."
        done
        ;;
    *) echo "🚫 Unknown command: ${command}" >&2; usage ;;
esac
