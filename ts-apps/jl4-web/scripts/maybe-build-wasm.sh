#!/bin/bash
# Build the WASM language server if static/wasm/ doesn't have it yet.
# The editor always runs the LSP in the browser from these files.
#
# Usage: ./scripts/maybe-build-wasm.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WASM_BUILD_SCRIPT="$PROJECT_ROOT/jl4-wasm/scripts/build-wasm.sh"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if WASM files exist (release builds put them in static/wasm/<release>/)
wasm_files_exist() {
    local WASM_DIR="$WEB_APP_DIR/static/wasm"
    if [ -n "$(find "$WASM_DIR" -name jl4-core.wasm 2>/dev/null | head -1)" ] &&
       [ -n "$(find "$WASM_DIR" -name jl4-core.mjs 2>/dev/null | head -1)" ]; then
        return 0
    fi
    return 1
}

# Main
main() {
    # Check if WASM files already exist
    if wasm_files_exist; then
        echo -e "${GREEN}[WASM] WASM files already exist, skipping build${NC}"
        echo -e "${YELLOW}[WASM] To force rebuild, delete static/wasm/ and run again${NC}"
        exit 0
    fi
    
    # Check if build script exists
    if [ ! -f "$WASM_BUILD_SCRIPT" ]; then
        echo -e "${YELLOW}[WASM] Build script not found: $WASM_BUILD_SCRIPT${NC}"
        echo -e "${YELLOW}[WASM] Please build WASM manually or copy pre-built files to static/wasm/${NC}"
        exit 1
    fi
    
    # Check if GHC WASM toolchain is available
    GHC_WASM_ENV="${GHC_WASM_ENV:-$HOME/.ghc-wasm/env}"
    if [ ! -f "$GHC_WASM_ENV" ]; then
        echo -e "${YELLOW}[WASM] GHC WASM toolchain not found at $GHC_WASM_ENV${NC}"
        echo -e "${YELLOW}[WASM] Install with: curl -L https://gitlab.haskell.org/haskell-wasm/ghc-wasm-meta/-/raw/master/bootstrap.sh | FLAVOUR=9.10 bash${NC}"
        echo -e "${YELLOW}[WASM] Or copy pre-built WASM files to static/wasm/${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}[WASM] Building WASM module...${NC}"
    "$WASM_BUILD_SCRIPT" --all
    
    echo -e "${GREEN}[WASM] Build complete${NC}"
}

main "$@"
