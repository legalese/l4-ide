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
REDIRECT_ERRORS=0
REDIRECT_OK=0

# Options
VERBOSE=false
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

# Convert markdown headings to their anchor form, one per line on stdin
# Rules: lowercase, spaces to hyphens, remove most special chars
headings_to_anchors() {
    tr '[:upper:]' '[:lower:]' | sed 's/ /-/g; s/[^a-z0-9_-]//g'
}

# Extract all valid anchors from a markdown file
# Returns one anchor per line
get_file_anchors() {
    local file="$1"

    # Headings (lines starting with #), without the # prefix and leading/trailing whitespace
    grep -E '^#{1,6} ' "$file" 2>/dev/null | sed -E 's/^#+ *//; s/ *$//' | headings_to_anchors || true

    # Also extract explicit anchor targets: {#anchor-name} or <a name="anchor"> or <a id="anchor">
    grep -oE '\{#[^}]+\}' "$file" 2>/dev/null | sed 's/{#//;s/}$//' || true
    grep -oE '<a [^>]*(name|id)="[^"]+"' "$file" 2>/dev/null | sed 's/.*[name|id]="//;s/"$//' || true
}

# The anchors of every file read so far, as "<file><TAB><anchor>" lines, and the
# files read. Each file is read once, however many links point into it. (Plain
# strings rather than an associative array, which the bash 3.2 on macOS lacks.)
ANCHOR_CACHE=$'\n'
ANCHOR_CACHE_FILES=$'\n'

# Check if an anchor exists in a file
anchor_exists() {
    local file="$1"
    local anchor="$2"
    local a

    if [[ "$ANCHOR_CACHE_FILES" != *$'\n'"$file"$'\n'* ]]; then
        while IFS= read -r a; do
            ANCHOR_CACHE+="$file"$'\t'"$a"$'\n'
        done < <(get_file_anchors "$file")
        ANCHOR_CACHE_FILES+="$file"$'\n'
    fi
    [[ "$ANCHOR_CACHE" == *$'\n'"$file"$'\t'"$anchor"$'\n'* ]]
}

# Set NORMALIZED to the absolute form of a path, by changing into its folder
# and back in this shell rather than in a subshell, which is costly on Windows.
# Empty if the folder does not exist.
normalize_path() {
    local path="$1"
    local dir base
    while [[ "$path" == */ && "$path" != / ]]; do path="${path%/}"; done
    dir="${path%/*}"
    base="${path##*/}"
    [[ "$dir" == "$path" ]] && dir="."
    [[ -z "$dir" ]] && dir="/"
    if CDPATH= cd "$dir" 2>/dev/null; then
        NORMALIZED="$PWD/$base"
        cd "$OLDPWD"
    else
        NORMALIZED=""
    fi
}

show_help() {
    cat << EOF
test-docs.sh - Validate L4 documentation

USAGE:
    ./doc/test-docs.sh [OPTIONS]

OPTIONS:
    --verbose, -v     Show all checks, not just errors
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

    4. Redirects (redirects.json)
       - Each old slug must no longer be a page
       - Each new slug (and #anchor, if given) must exist

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

# Every file a link resolves to, for the orphan check (part 3)
LINKED_FILES_TMP=$(mktemp)
trap "rm -f $LINKED_FILES_TMP" EXIT

check_link() {
    local source_file="$1"
    local link="$2"
    local source_dir="${source_file%/*}"
    
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
    
    # Normalize the path, and record it for the orphan check (part 3)
    normalize_path "$resolved_path"
    resolved_path="$NORMALIZED"
    [[ -n "$resolved_path" ]] && echo "$resolved_path" >> "$LINKED_FILES_TMP"

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
    else
        log_warn "l4 CLI not built. Run 'cabal build jl4:l4' first."
        log_warn "Skipping L4 validation"
    fi
else
    log_warn "l4 CLI not found and cabal not available"
    log_warn "Skipping L4 validation"
fi

if $JL4_AVAILABLE; then
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

# The files the links in part 1 resolve to, sorted and deduplicated, as one
# string to look each file up in
sort -u "$LINKED_FILES_TMP" -o "$LINKED_FILES_TMP"
LINKED_FILES=$'
'"$(< "$LINKED_FILES_TMP")"$'
'

# Now check all .md and .l4 files to see if they're linked
while IFS= read -r -d '' file; do
    relative_path="${file#$SCRIPT_DIR/}"
    filename="${file##*/}"
    
    # Skip README.md and SUMMARY.md files - they are index files
    if [[ "$filename" == "README.md" ]] || [[ "$filename" == "SUMMARY.md" ]]; then
        log_verbose "  [SKIP] Index file: $relative_path"
        ((ORPHAN_OK+=1))
        continue
    fi
    
    # Check if this file is linked from anywhere (exact match)
    if [[ "$LINKED_FILES" == *$'
'"$file"$'
'* ]]; then
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
# PART 4: Check Redirects
# =============================================================================
# redirects.json maps the slug of a page that moved or was merged away to its
# new slug, optionally with #anchor. The website publishes a redirect at each
# old URL, so the old page must be gone and the new one must exist.

echo ""
log_info "Checking redirects..."
echo ""

REDIRECTS_FILE="$SCRIPT_DIR/redirects.json"

# The page file for a slug: <slug>.md, or <slug>/README.md for a folder
slug_to_file() {
    local slug="$1"
    if [[ -z "$slug" ]]; then
        echo "$SCRIPT_DIR/README.md"
    elif [[ -f "$SCRIPT_DIR/$slug.md" ]]; then
        echo "$SCRIPT_DIR/$slug.md"
    elif [[ -f "$SCRIPT_DIR/$slug/README.md" ]]; then
        echo "$SCRIPT_DIR/$slug/README.md"
    fi
}

if [[ -f "$REDIRECTS_FILE" ]]; then
    if ! redirect_lines=$(python3 -c 'import json, sys
for old, new in json.load(open(sys.argv[1])).items():
    print(old + "\t" + new)' "$REDIRECTS_FILE"); then
        log_error "redirects.json is not a valid JSON object"
        ((REDIRECT_ERRORS+=1))
        redirect_lines=""
    fi

    while IFS=$'\t' read -r old new; do
        [[ -z "$old" ]] && continue
        # Python on Windows ends its lines with CRLF
        new="${new%$'\r'}"
        new_slug="${new%%#*}"
        anchor=""
        [[ "$new" == *"#"* ]] && anchor="${new#*#}"

        if [[ -n "$(slug_to_file "$old")" ]]; then
            log_error "Redirect from a page that still exists: $old"
            ((REDIRECT_ERRORS+=1))
            continue
        fi

        target="$(slug_to_file "$new_slug")"
        if [[ -z "$target" ]]; then
            log_error "Redirect to a missing page: $old -> $new"
            ((REDIRECT_ERRORS+=1))
        elif [[ -n "$anchor" ]] && ! anchor_exists "$target" "$anchor"; then
            log_error "Redirect to a missing anchor: $old -> $new"
            ((REDIRECT_ERRORS+=1))
        else
            log_verbose "  [OK] $old -> $new"
            ((REDIRECT_OK+=1))
        fi
    done <<< "$redirect_lines"
fi

if [[ $REDIRECT_ERRORS -eq 0 ]]; then
    log_success "All $REDIRECT_OK redirects point at existing pages"
else
    log_error "$REDIRECT_ERRORS broken redirects found ($REDIRECT_OK valid)"
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
echo "  L4 files:        $L4_OK valid, $L4_ERRORS errors"
echo "  Orphan check:    $ORPHAN_OK linked, $ORPHAN_ERRORS orphaned"
echo "  Redirects:       $REDIRECT_OK valid, $REDIRECT_ERRORS errors"
echo ""

TOTAL_ERRORS=$((LINK_ERRORS + L4_ERRORS + ORPHAN_ERRORS + REDIRECT_ERRORS))

if [[ $TOTAL_ERRORS -eq 0 ]]; then
    log_success "All documentation checks passed!"
    exit 0
else
    log_error "$TOTAL_ERRORS total errors found"
    exit 1
fi
