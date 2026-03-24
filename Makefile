# Copyright (c) 2026 Pius Alfred
# License: MIT

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
GOTOOLS       := ./gotools.sh
ADDLICENSE    := $(GOTOOLS) exec addlicense
GOFUMPT       := $(GOTOOLS) exec gofumpt
GCI           := $(GOTOOLS) exec gci

MODULE        := github.com/piusalfred/gotools
LICENSE_TYPE  := mit
LICENSE_OWNER := Pius Alfred

# Directories / files to ignore when applying license headers.
LICENSE_IGNORE := \
	-ignore "tools/**"   \
	-ignore ".idea/**"   \
	-ignore ".gitignore" \
	-ignore "go.work"

# gci import section ordering:
#   1. standard library
#   2. default (third-party)
#   3. this module's packages
GCI_SECTIONS := \
	-s standard \
	-s default \
	-s "prefix($(MODULE))"

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------
.PHONY: fmt fmt-license fmt-imports fmt-go fmt-mod help

## fmt: autofix license headers, organise imports, format Go source, and tidy modules
fmt: fmt-license fmt-imports fmt-go fmt-mod

## fmt-license: add or fix missing license headers on all source files
fmt-license:
	@echo "📝 Fixing license headers..."
	$(ADDLICENSE) -l $(LICENSE_TYPE) -c "$(LICENSE_OWNER)" $(LICENSE_IGNORE) .

## fmt-imports: group and sort imports with gci
fmt-imports:
	@echo "🔀 Organising imports..."
	$(GCI) write $(GCI_SECTIONS) .

## fmt-go: format all Go source files with gofumpt (strict gofmt superset)
fmt-go:
	@echo "🔧 Formatting Go source files..."
	$(GOFUMPT) -w -extra .

## fmt-mod: tidy the root go.mod
fmt-mod:
	@echo "📦 Tidying go.mod..."
	go mod tidy

## help: show this help message
help:
	@echo "Usage: make [target]"
	@echo ""
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /' | column -t -s ':'
