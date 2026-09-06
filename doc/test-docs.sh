#!/usr/bin/env bash
# test-docs.sh - Validate documentation links and L4 examples
# Usage: ./doc/test-docs.sh [--fix-links] [--verbose]

set -euo pipefail

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
LINK_ERRORS=0
LINK_WARNINGS=0
LINK_OK=0
L4_ERRORS=0
L4_OK=0
ORPHAN_ERRORS=0
ORPHAN_OK=0

# Options
VERBOSE=false

# Whether PART 2 (l4 CLI validation) is deliberately skipped. This must be an
# explicit choice, never an inferred one: see the fatal branch in PART 2.
SKIP_L4=false
FIX_LINKS=false

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_verbose() {
    if $VERBOSE; then
        echo -e "       $1"
    fi
}

# Convert a markdown heading to its anchor form
# Rules: lowercase, spaces to hyphens, remove most special chars
heading_to_anchor() {
    local heading="$1"
    echo "$heading" | \
        tr '[:upper:]' '[:lower:]' | \
        sed 's/ /-/g' | \
        sed 's/[^a-z0-9_-]//g'
}

# Extract all valid anchors from a markdown file
# Returns one anchor per line
get_file_anchors() {
    local file="$1"
    
    # Extract headings (lines starting with #)
    grep -E '^#{1,6} ' "$file" 2>/dev/null | while IFS= read -r line; do
        # Remove the # prefix and leading/trailing whitespace
        heading=$(echo "$line" | sed -E 's/^#+ *//' | sed 's/ *$//')
        heading_to_anchor "$heading"
    done
    
    # Also extract explicit anchor targets: {#anchor-name} or <a name="anchor"> or <a id="anchor">
    grep -oE '\{#[^}]+\}' "$file" 2>/dev/null | sed 's/{#//;s/}$//' || true
    grep -oE '<a [^>]*(name|id)="[^"]+"' "$file" 2>/dev/null | sed 's/.*[name|id]="//;s/"$//' || true
}

# Check if an anchor exists in a file
anchor_exists() {
    local file="$1"
    local anchor="$2"
    
    # Get all anchors and check if our anchor is among them
    get_file_anchors "$file" | grep -qFx "$anchor"
}

show_help() {
    cat << EOF
test-docs.sh - Validate L4 documentation

USAGE:
    ./doc/test-docs.sh [OPTIONS]

OPTIONS:
    --verbose, -v     Show all checks, not just errors
    --no-l4           Skip PART 2 (l4 CLI validation) deliberately. Without
                      this flag, a missing l4 CLI is a FATAL error, not a
                      warning: parts 1 and 3 need no build and are safe to run
                      anywhere, but "l4 files: 0 valid" must never be
                      indistinguishable from "l4 files: all valid".
    --help, -h        Show this help message

CHECKS:
    1. Markdown link validation
       - Checks that all relative links point to existing files
       - Validates anchor links (#heading) reference valid headings
       - Validates cross-file anchors (file.md#heading) exist
       - Reports external links (not validated)
       - Errors on links pointing to folders instead of files

    2. L4 file validation
       - Validates all .l4 files in the doc/ folder
       - Uses the l4 CLI for syntax and type checking

    3. Orphan file detection
       - Finds .md and .l4 files not linked from any other file
       - README.md and SUMMARY.md files are exempt (they are index files)

EXAMPLES:
    ./doc/test-docs.sh              # Run all checks
    ./doc/test-docs.sh --verbose    # Show all results, not just errors

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --no-l4)
            SKIP_L4=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check if we're in the right directory
if [[ ! -d "$SCRIPT_DIR/courses" ]] || [[ ! -d "$SCRIPT_DIR/reference" ]]; then
    log_error "This script must be run from the repository root or doc/ directory"
    exit 1
fi

echo ""
echo "========================================"
echo "  L4 Documentation Test Suite"
echo "========================================"
echo ""

# =============================================================================
# PART 1: Check Markdown Links
# =============================================================================

log_info "Checking markdown links..."
echo ""

check_link() {
    local source_file="$1"
    local link="$2"
    local source_dir
    source_dir="$(dirname "$source_file")"
    
    # Skip external links
    if [[ "$link" =~ ^https?:// ]] || [[ "$link" =~ ^mailto: ]]; then
        log_verbose "  [SKIP] External: $link"
        return 0
    fi
    
    # Handle anchor-only links (same file)
    if [[ "$link" =~ ^# ]]; then
        local same_file_anchor="${link#\#}"
        if anchor_exists "$source_file" "$same_file_anchor"; then
            ((LINK_OK+=1))
            log_verbose "  [OK] $link (same-file anchor)"
        else
            log_error "Broken anchor in $source_file"
            echo "       Anchor: $link"
            echo "       No heading found that generates anchor: $same_file_anchor"
            ((LINK_ERRORS+=1))
        fi
        return 0
    fi
    
    # Extract the file path (remove anchor if present)
    local file_path="${link%%#*}"
    local anchor="${link#*#}"
    [[ "$anchor" == "$link" ]] && anchor=""
    
    # Skip empty paths (pure anchors already handled)
    if [[ -z "$file_path" ]]; then
        return 0
    fi
    
    # Resolve the path relative to the source file
    local resolved_path
    if [[ "$file_path" =~ ^/ ]]; then
        # Absolute path from repo root
        resolved_path="$REPO_ROOT$file_path"
    else
        # Relative path from source file
        resolved_path="$source_dir/$file_path"
    fi
    
    # Normalize the path
    resolved_path="$(cd "$(dirname "$resolved_path")" 2>/dev/null && pwd)/$(basename "$resolved_path")" 2>/dev/null || resolved_path=""
    
    # Check if file exists
    if [[ -z "$resolved_path" ]] || [[ ! -e "$resolved_path" ]]; then
        log_error "Broken link in $source_file"
        echo "       Link: $link"
        echo "       Expected: $source_dir/$file_path"
        ((LINK_ERRORS+=1))
        return 1
    fi
    
    # Check if it's a directory (error if so)
    if [[ -d "$resolved_path" ]]; then
        log_error "Link to folder in $source_file"
        echo "       Link: $link"
        echo "       Resolved to folder: $resolved_path"
        ((LINK_ERRORS+=1))
        return 1
    fi
    
    # If there's an anchor, validate it exists in the target file
    if [[ -n "$anchor" ]]; then
        # Only check anchors for markdown files
        if [[ "$resolved_path" =~ \.md$ ]]; then
            if ! anchor_exists "$resolved_path" "$anchor"; then
                log_error "Broken anchor in $source_file"
                echo "       Link: $link"
                echo "       File exists but anchor '#$anchor' not found"
                ((LINK_ERRORS+=1))
                return 1
            fi
        fi
    fi
    
    ((LINK_OK+=1))
    log_verbose "  [OK] $link"
    return 0
}

# Find all markdown files and check their links
while IFS= read -r -d '' md_file; do
    relative_path="${md_file#$SCRIPT_DIR/}"
    log_verbose "Checking: $relative_path"
    
    # Extract markdown links: [text](link) and [text]: link
    # Using grep to find links, then process them
    while IFS= read -r link; do
        # Skip empty lines
        [[ -z "$link" ]] && continue
        check_link "$md_file" "$link" || true
    done < <(grep -oE '\]\([^)]+\)' "$md_file" 2>/dev/null | sed 's/\](//;s/)$//' || true)
    
    # Also check reference-style links [text]: url
    while IFS= read -r link; do
        [[ -z "$link" ]] && continue
        check_link "$md_file" "$link" || true
    done < <(grep -oE '^\[.*\]: .+$' "$md_file" 2>/dev/null | sed 's/^\[.*\]: //' || true)
    
done < <(find "$SCRIPT_DIR" -name "*.md" -type f -print0)

echo ""
if [[ $LINK_ERRORS -eq 0 ]]; then
    log_success "All $LINK_OK markdown links are valid"
else
    log_error "$LINK_ERRORS broken or folder links found ($LINK_OK valid)"
fi

# =============================================================================
# PART 2: Validate L4 Files
# =============================================================================

echo ""
log_info "Validating L4 files..."
echo ""

# Function to run the l4 CLI - handles both direct invocation and cabal run
run_l4_cli() {
    local file="$1"
    if [[ -n "$L4_CLI_DIRECT" ]]; then
        "$L4_CLI_DIRECT" run "$file" 2>&1
    else
        # Run from repo root for proper library resolution.
        # cabal run sets up data-files paths correctly; JL4_LIBRARY_PATH
        # prefers local libraries over any installed copy.
        (cd "$REPO_ROOT" && JL4_LIBRARY_PATH="${JL4_LIBRARY_PATH:-jl4-core/libraries}" cabal run jl4:l4 -v0 -- run "$file" 2>&1)
    fi
}

# Check if the l4 CLI is available
L4_CLI_DIRECT=""
JL4_AVAILABLE=false

# NOTE: an `l4` on PATH WINS over this worktree's freshly built one. That is
# right for a reader checking out the docs and wrong for anyone developing a
# language feature: an INSTALLED binary older than the tree cannot parse syntax
# the tree just added, and the failure reads as "this doc page has a broken
# example" rather than "your `l4` is old". If a doc `.l4` fails on a construct
# you know is valid, check `which l4` first, and either put this worktree's
# `dist-newstyle/.../l4` earlier on PATH or run with a PATH that has no `l4`
# so the `cabal list-bin` branch below is taken. (Measured 2026-09-04: a 27 Aug
# ~/.local/bin/l4 rejected a REFUSE example added the same day.)
if command -v l4 &> /dev/null; then
    L4_CLI_DIRECT="l4"
    JL4_AVAILABLE=true
    log_verbose "Using l4 from PATH"
elif command -v cabal &> /dev/null; then
    # Try to find the built binary using cabal list-bin (fully qualified name)
    L4_BIN=""
    set +e  # Temporarily disable exit on error for cabal command
    L4_BIN=$(cd "$REPO_ROOT" && cabal list-bin jl4:l4 2>/dev/null)
    CABAL_EXIT=$?
    set -e

    if [[ $CABAL_EXIT -eq 0 && -n "$L4_BIN" && -x "$L4_BIN" ]]; then
        JL4_AVAILABLE=true
        log_verbose "Using cabal run jl4:l4"
    fi
fi

# A missing l4 CLI used to be two log_warn lines and a skip. That is the one
# failure mode this suite cannot afford: the summary below still printed
# "L4 files: 0 valid, 0 errors" and the script still exited 0, so a run that
# checked nothing was indistinguishable from a run that checked everything —
# which is exactly the failure the unfiltered corpus-goldens job in
# pr-checks.yml exists to prevent, reproduced inside the doc suite.
#
# So the choice is now explicit and one of two: pass --no-l4 and be told loudly
# that PART 2 did not run, or have the binary. There is no third state.
if ! $JL4_AVAILABLE && ! $SKIP_L4; then
    log_error "l4 CLI not available (not on PATH, and 'cabal list-bin jl4:l4' found no built binary)."
    log_error "Build it with 'cabal build jl4:l4', or pass --no-l4 to skip PART 2 deliberately."
    exit 1
fi

if $SKIP_L4; then
    log_warn "PART 2 SKIPPED by --no-l4: no .l4 file under doc/ was validated."
fi

if $JL4_AVAILABLE && ! $SKIP_L4; then
    # Find all .l4 files in doc/
    while IFS= read -r -d '' l4_file; do
        relative_path="${l4_file#$SCRIPT_DIR/}"
        
        # Run l4 CLI and capture output
        set +e  # Disable exit on error for this command
        output=$(run_l4_cli "$l4_file")
        run_exit_code=$?
        set -e  # Re-enable
        
        if [[ $run_exit_code -eq 0 ]]; then
            # Check if there are actual errors (not just #EVAL output containing "error" text)
            # Real errors have "Severity: DiagnosticSeverity_Error" while #EVAL output has "Information"
            if echo "$output" | grep -qi "DiagnosticSeverity_Error"; then
                log_error "Validation failed: $relative_path"
                echo "$output" | head -20 | sed 's/^/       /'
                ((L4_ERRORS+=1))
            else
                ((L4_OK+=1))
                log_verbose "[OK] $relative_path"
            fi
        else
            log_error "Validation failed: $relative_path"
            echo "$output" | head -20 | sed 's/^/       /'
            ((L4_ERRORS+=1))
        fi
    done < <(find "$SCRIPT_DIR" -name "*.l4" -type f -print0)
    
    echo ""
    if [[ $L4_ERRORS -eq 0 ]]; then
        if [[ $L4_OK -eq 0 ]]; then
            log_warn "No .l4 files found in doc/"
        else
            log_success "All $L4_OK L4 files are valid"
        fi
    else
        log_error "$L4_ERRORS L4 files have errors ($L4_OK valid)"
    fi
fi

# =============================================================================
# PART 3: Check for Orphaned Files
# =============================================================================

echo ""
log_info "Checking for orphaned files..."
echo ""

# Create a temporary file to store all linked file paths
LINKED_FILES_TMP=$(mktemp)
trap "rm -f $LINKED_FILES_TMP" EXIT

# First, collect all links from all markdown files and resolve them to absolute paths
while IFS= read -r -d '' md_file; do
    source_dir="$(dirname "$md_file")"
    
    # Extract markdown links: [text](link)
    while IFS= read -r link; do
        [[ -z "$link" ]] && continue
        
        # Skip external links and anchors
        [[ "$link" =~ ^https?:// ]] && continue
        [[ "$link" =~ ^mailto: ]] && continue
        [[ "$link" =~ ^# ]] && continue
        
        # Extract the file path (remove anchor if present)
        file_path="${link%%#*}"
        [[ -z "$file_path" ]] && continue
        
        # Resolve the path relative to the source file
        if [[ "$file_path" =~ ^/ ]]; then
            resolved_path="$REPO_ROOT$file_path"
        else
            resolved_path="$source_dir/$file_path"
        fi
        
        # Normalize the path and add to temp file
        normalized="$(cd "$(dirname "$resolved_path")" 2>/dev/null && pwd)/$(basename "$resolved_path")" 2>/dev/null
        [[ -n "$normalized" ]] && echo "$normalized" >> "$LINKED_FILES_TMP"
    done < <(grep -oE '\]\([^)]+\)' "$md_file" 2>/dev/null | sed 's/\](//;s/)$//' || true)
    
    # Also check reference-style links [text]: url
    while IFS= read -r link; do
        [[ -z "$link" ]] && continue
        
        # Skip external links
        [[ "$link" =~ ^https?:// ]] && continue
        [[ "$link" =~ ^mailto: ]] && continue
        
        file_path="${link%%#*}"
        [[ -z "$file_path" ]] && continue
        
        if [[ "$file_path" =~ ^/ ]]; then
            resolved_path="$REPO_ROOT$file_path"
        else
            resolved_path="$source_dir/$file_path"
        fi
        
        normalized="$(cd "$(dirname "$resolved_path")" 2>/dev/null && pwd)/$(basename "$resolved_path")" 2>/dev/null
        [[ -n "$normalized" ]] && echo "$normalized" >> "$LINKED_FILES_TMP"
    done < <(grep -oE '^\[.*\]: .+$' "$md_file" 2>/dev/null | sed 's/^\[.*\]: //' || true)
    
done < <(find "$SCRIPT_DIR" -name "*.md" -type f -print0)

# Sort and dedupe the linked files list
sort -u "$LINKED_FILES_TMP" -o "$LINKED_FILES_TMP"

# Now check all .md and .l4 files to see if they're linked
while IFS= read -r -d '' file; do
    relative_path="${file#$SCRIPT_DIR/}"
    filename="$(basename "$file")"
    
    # Skip README.md and SUMMARY.md files - they are index files
    if [[ "$filename" == "README.md" ]] || [[ "$filename" == "SUMMARY.md" ]]; then
        log_verbose "  [SKIP] Index file: $relative_path"
        ((ORPHAN_OK+=1))
        continue
    fi
    
    # Check if this file is linked from anywhere (grep for exact match)
    if grep -qFx "$file" "$LINKED_FILES_TMP"; then
        log_verbose "  [OK] $relative_path"
        ((ORPHAN_OK+=1))
    else
        log_error "Orphaned file (not linked from anywhere): $relative_path"
        ((ORPHAN_ERRORS+=1))
    fi
    
done < <(find "$SCRIPT_DIR" \( -name "*.md" -o -name "*.l4" \) -type f -print0)

echo ""
if [[ $ORPHAN_ERRORS -eq 0 ]]; then
    log_success "All $ORPHAN_OK files are properly linked"
else
    log_error "$ORPHAN_ERRORS orphaned files found ($ORPHAN_OK linked)"
fi

# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo "========================================"
echo "  Summary"
echo "========================================"
echo ""
echo "  Markdown links:  $LINK_OK valid, $LINK_ERRORS errors"
if $SKIP_L4; then
    echo "  L4 files:        NOT CHECKED (--no-l4)"
else
    echo "  L4 files:        $L4_OK valid, $L4_ERRORS errors"
fi
echo "  Orphan check:    $ORPHAN_OK linked, $ORPHAN_ERRORS orphaned"
echo ""

TOTAL_ERRORS=$((LINK_ERRORS + L4_ERRORS + ORPHAN_ERRORS))

if [[ $TOTAL_ERRORS -eq 0 ]]; then
    log_success "All documentation checks passed!"
    exit 0
else
    log_error "$TOTAL_ERRORS total errors found"
    exit 1
fi
