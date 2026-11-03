#!/bin/bash
#
# Test: Custom character mapping via Git clean/smudge filters
#
# Use case (from community discussion):
#   Git relies on iconv for working-tree-encoding conversion and offers no
#   way to define custom character mappings. Someone may want EBCDIC
#   characters to map to a DIFFERENT UTF-8 character (or string) than the
#   one iconv's built-in tables choose.
#
#   The closest supported option is Git's filter.<name>.clean/smudge
#   attributes (.gitattributes). The filter runs your own script on
#   check-in (clean: working tree -> Git) and check-out (smudge: Git ->
#   working tree), so you can perform any mapping you like.
#
# This test demonstrates on z/OS:
#   Test 1: EBCDIC cent sign (IBM-1047 0x4A) is stored in Git as the
#           ASCII string "CENT" instead of iconv's choice (U+00A2).
#   Test 2: EBCDIC cent sign (IBM-1047 0x4A) is stored in Git as a
#           different UTF-8 character (U+00A4 CURRENCY SIGN) instead of
#           iconv's choice (U+00A2 CENT SIGN).
#
# Both tests verify the full round trip:
#   working tree (EBCDIC) --clean--> blob (custom UTF-8/ASCII)
#   blob (custom UTF-8/ASCII) --smudge--> working tree (EBCDIC, original bytes)
#
# The mapping is fully under the user's control - change the sed
# expression in the filter scripts to map to whatever you want.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="${SCRIPT_DIR}/test_custom_char_mapping_filter_$$"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

cleanup() {
    if [ -d "$TEST_DIR" ]; then
        cd "$SCRIPT_DIR"
        rm -rf "$TEST_DIR"
    fi
}

trap cleanup EXIT

log_info()    { echo -e "${YELLOW}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $1"; }

run_test()  { TESTS_RUN=$((TESTS_RUN + 1)); log_info "Running test $TESTS_RUN: $1"; }
pass_test() { TESTS_PASSED=$((TESTS_PASSED + 1)); log_success "$1"; }
fail_test() { TESTS_FAILED=$((TESTS_FAILED + 1)); log_error "$1"; }

# Compare two files byte-for-byte. Both are first re-tagged with the same
# codepage so tag-honoring tools compare the raw bytes identically.
rawcmp() {
    chtag -tc ISO8859-1 "$1" 2>/dev/null || chtag -r "$1" 2>/dev/null || true
    chtag -tc ISO8859-1 "$2" 2>/dev/null || chtag -r "$2" 2>/dev/null || true
    cmp -s "$1" "$2"
}

setup_repo() {
    cd "$TEST_DIR"
    rm -rf .git
    git init -q -b main
    git config core.ignorefiletags true  # raw bytes to/from the filters
    git config user.email "test@example.com"
    git config user.name "Test User"
}

#
# Test 1: map EBCDIC cent sign to the ASCII string "CENT" in the Git blob
#
test_map_to_string() {
    run_test "Map EBCDIC cent sign (0x4A) to ASCII string 'CENT' in blob"

    setup_repo

    # Filter scripts: the whole conversion is ours, iconv is only used as
    # the base EBCDIC<->UTF-8 converter; the sed does the custom mapping.
    #
    # clean  (check-in):  EBCDIC bytes -> UTF-8 -> replace U+00A2 with CENT
    # smudge (check-out): replace CENT with U+00A2 -> UTF-8 -> EBCDIC bytes
    cat > clean-map.sh  <<'EOF'
#!/bin/sh
iconv -f IBM-1047 -t UTF-8 | sed 's/\xc2\xa2/CENT/g'
EOF
    cat > smudge-map.sh <<'EOF'
#!/bin/sh
sed 's/CENT/\xc2\xa2/g' | iconv -f UTF-8 -t IBM-1047
EOF
    chmod +x clean-map.sh smudge-map.sh

    git config filter.ebcdicmap.clean  "$TEST_DIR/clean-map.sh"
    git config filter.ebcdicmap.smudge "$TEST_DIR/smudge-map.sh"
    git config filter.ebcdicmap.required true

    echo "*.dat filter=ebcdicmap" > .gitattributes

    # Working tree file: "AB<cent>CD" in IBM-1047 (0x4A = cent sign)
    printf '\xc1\xc2\x4a\xc3\xc4' > data.dat

    git add .gitattributes data.dat
    git commit -q -m "Add EBCDIC data file"

    # The blob must contain the custom mapping ("ABCENTCD"), NOT iconv's
    # choice (UTF-8 cent sign U+00A2 = c2 a2).
    git cat-file blob HEAD:data.dat > blob.out
    if grep -q "ABCENTCD" blob.out && ! od -An -tx1 blob.out | grep -q "c2 a2"; then
        pass_test "Blob contains custom string 'CENT' (not iconv's U+00A2)"
    else
        fail_test "Blob does not contain the custom mapping"
        od -An -tx1 blob.out
        return 1
    fi

    # Round trip: remove and check out; the working tree file must be
    # restored to the original EBCDIC bytes.
    rm -f data.dat
    git checkout HEAD -- data.dat

    printf '\xc1\xc2\x4a\xc3\xc4' > expected.dat
    if [ -f data.dat ] && rawcmp expected.dat data.dat; then
        pass_test "Working tree round-tripped to original EBCDIC bytes"
    else
        fail_test "Working tree round-trip failed"
        od -An -tx1 data.dat 2>/dev/null
        return 1
    fi
}

#
# Test 2: map EBCDIC cent sign to a DIFFERENT UTF-8 character (U+00A4)
#         than the one iconv proposes (U+00A2)
#
test_map_to_different_utf8_char() {
    run_test "Map EBCDIC cent sign (0x4A) to different UTF-8 char (U+00A4)"

    setup_repo

    # iconv maps IBM-1047 0x4A to UTF-8 U+00A2 (c2 a2). We want U+00A4
    # (c2 a4, currency sign) instead. The smudge reverses the mapping
    # before converting back to EBCDIC.
    cat > clean-map2.sh  <<'EOF'
#!/bin/sh
iconv -f IBM-1047 -t UTF-8 | sed 's/\xc2\xa2/\xc2\xa4/g'
EOF
    cat > smudge-map2.sh <<'EOF'
#!/bin/sh
sed 's/\xc2\xa4/\xc2\xa2/g' | iconv -f UTF-8 -t IBM-1047
EOF
    chmod +x clean-map2.sh smudge-map2.sh

    git config filter.ebcdicmap2.clean  "$TEST_DIR/clean-map2.sh"
    git config filter.ebcdicmap2.smudge "$TEST_DIR/smudge-map2.sh"
    git config filter.ebcdicmap2.required true

    echo "*.dat filter=ebcdicmap2" > .gitattributes

    printf '\xc1\xc2\x4a\xc3\xc4' > data.dat

    git add .gitattributes data.dat
    git commit -q -m "Add EBCDIC data file"

    # The blob must contain U+00A4 (c2 a4), not iconv's U+00A2 (c2 a2).
    git cat-file blob HEAD:data.dat > blob.out
    if od -An -tx1 blob.out | grep -q "c2 a4" && ! od -An -tx1 blob.out | grep -q "c2 a2"; then
        pass_test "Blob contains custom char U+00A4 (not iconv's U+00A2)"
    else
        fail_test "Blob does not contain the custom character"
        od -An -tx1 blob.out
        return 1
    fi

    # Round trip back to the original EBCDIC bytes.
    rm -f data.dat
    git checkout HEAD -- data.dat

    printf '\xc1\xc2\x4a\xc3\xc4' > expected.dat
    if [ -f data.dat ] && rawcmp expected.dat data.dat; then
        pass_test "Working tree round-tripped to original EBCDIC bytes"
    else
        fail_test "Working tree round-trip failed"
        od -An -tx1 data.dat 2>/dev/null
        return 1
    fi
}

main() {
    log_info "Custom character mapping via clean/smudge filters"
    log_info "=================================================="

    mkdir -p "$TEST_DIR"

    test_map_to_string
    test_map_to_different_utf8_char

    echo ""
    log_info "Test Summary:"
    log_info "  Total:  $TESTS_RUN"
    log_success "Passed: $TESTS_PASSED"

    if [ $TESTS_FAILED -gt 0 ]; then
        log_error "Failed: $TESTS_FAILED"
        exit 1
    else
        log_success "All tests passed!"
        exit 0
    fi
}

main "$@"
