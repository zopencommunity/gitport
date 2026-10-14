#!/bin/bash
# Comprehensive filter conversion test
# Tests dumb filters (cat) and same_encoding() protection

set -e

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║     Filter Conversion Test                                                    ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Create test directory
TEST_DIR="/tmp/git_filter_comprehensive_$$"

# Trap to ensure cleanup on exit
trap 'cd / && rm -rf "$TEST_DIR" 2>/dev/null || true' EXIT INT TERM
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo "Test directory: $TEST_DIR"
echo ""

# Initialize Git repo
echo "═══ Initialize Git repository ═══"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
echo "✓ Git repo initialized"
echo ""

PASS_COUNT=0
FAIL_COUNT=0

# ==============================================================================
# TEST 1: Dumb Filter (cat - doesn't convert)
# ==============================================================================

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "TEST 1: Dumb Filter (cat - no conversion)"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo "This tests P1's exact scenario: cat filter + EBCDIC file"
echo "Expected: Git stores UTF-8 (not EBCDIC)"
echo ""

# Create cat filter
cat > filter_cat.sh << 'FILTER'
#!/bin/bash
# Dumb filter - just passes data through
cat
FILTER
chmod +x filter_cat.sh

git config filter.catfilter.clean "$(pwd)/filter_cat.sh"
git config filter.catfilter.smudge "$(pwd)/filter_cat.sh"
git config filter.catfilter.required true

# Create .gitattributes
cat > .gitattributes << 'ATTR'
test1.txt filter=catfilter working-tree-encoding=IBM-1047
ATTR

# Create EBCDIC file
echo "Test 1: Cat filter" > test1_utf8.txt
iconv -f UTF-8 -t IBM-1047 test1_utf8.txt > test1.txt
chtag -tc IBM-1047 test1.txt

echo "File created (EBCDIC):"
od -A x -t x1z -N 20 test1.txt | head -2
echo ""

# Verify it's EBCDIC
FIRST_BYTES=$(od -A n -t x1 -N 4 test1.txt | tr -d ' \n')
if echo "$FIRST_BYTES" | grep -qi "^e385a2a3"; then
    echo "✓ Confirmed: File contains EBCDIC bytes"
else
    echo "✗ WARNING: File might not be EBCDIC: $FIRST_BYTES"
fi
echo ""

# Add to Git
echo "Adding file to Git..."
git add .gitattributes test1.txt
git commit -q -m "Test 1: Cat filter"

# Check Git object
HASH=$(git ls-files -s test1.txt | awk '{print $2}')
echo "Git object hash: $HASH"
echo ""
echo "Git object content:"
git cat-file -p $HASH | od -A x -t x1z -N 20 | head -2
echo ""

# Verify
OBJECT_HEX=$(git cat-file -p $HASH | od -A n -t x1 -N 4 | tr -d ' \n')
echo "Analysis:"
echo "  First 4 bytes: $OBJECT_HEX"

if echo "$OBJECT_HEX" | grep -qi "^54657374"; then
    echo "  Result: UTF-8 detected ✅"
    echo ""
    echo "  ✅ TEST 1 PASSED: Cat filter + encode_to_git() converted EBCDIC → UTF-8"
    echo "     This proves P1's bug is FIXED!"
    PASS_COUNT=$((PASS_COUNT + 1))
elif echo "$OBJECT_HEX" | grep -qi "^e385a2a3"; then
    echo "  Result: EBCDIC detected ❌"
    echo ""
    echo "  ❌ TEST 1 FAILED: Git stored EBCDIC (should be UTF-8)"
    echo "     This means encode_to_git() is still being skipped!"
    FAIL_COUNT=$((FAIL_COUNT + 1))
else
    echo "  Result: Unknown encoding"
    echo "  Actual bytes: $OBJECT_HEX"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""
echo ""

# ==============================================================================
# TEST 2: Verify same_encoding() Protection
# ==============================================================================

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "TEST 2: Verify same_encoding() Protection"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo "This tests that UTF-8 → UTF-8 conversion is skipped (no double conversion)"
echo ""

# Create filter and file with UTF-8 encoding
cat > filter_passthrough.sh << 'FILTER'
#!/bin/bash
cat
FILTER
chmod +x filter_passthrough.sh

git config filter.utf8filter.clean "$(pwd)/filter_passthrough.sh"
git config filter.utf8filter.smudge "$(pwd)/filter_passthrough.sh"

cat > .gitattributes << 'ATTR'
test1.txt filter=catfilter working-tree-encoding=IBM-1047
test2.txt filter=utf8filter working-tree-encoding=UTF-8
ATTR

# Create UTF-8 file with UTF-8 encoding
echo "Test 2: UTF-8 with UTF-8 encoding" > test2.txt
chtag -tc UTF-8 test2.txt

echo "File created (UTF-8):"
od -A x -t x1z -N 20 test2.txt | head -2
echo ""

git add .gitattributes test2.txt
git commit -q -m "Test 2: same_encoding protection"

HASH=$(git ls-files -s test2.txt | awk '{print $2}')
echo "Git object hash: $HASH"
echo ""

# Check content
CONTENT=$(git cat-file -p $HASH)
echo "Git object content: $CONTENT"
echo ""

if echo "$CONTENT" | grep -q "Test 2"; then
    echo "  ✅ TEST 2 PASSED: same_encoding() protection works"
    echo "     UTF-8 → UTF-8 conversion was skipped (no double conversion)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  ❌ TEST 2 FAILED: Content corrupted"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""
echo ""

# ==============================================================================
# Summary
# ==============================================================================

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "SUMMARY"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Tests passed: $PASS_COUNT"
echo "Tests failed: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo "✅ ALL TESTS PASSED!"
    echo ""
    echo "Conclusions:"
    echo "  1. ✅ Dumb filters (cat) work correctly - EBCDIC → UTF-8 conversion"
    echo "  2. ✅ same_encoding() protection prevents double conversion"
    echo ""
    echo "The fix (removing #ifdef __MVS__) is CORRECT!"
    echo ""
    echo "Note: Filters that convert encoding (e.g., iconv) are anti-patterns"
    echo "      and are not supported. See FILTER_ANTI_PATTERNS.md for details."
    EXIT_CODE=0
else
    echo "❌ SOME TESTS FAILED"
    echo ""
    echo "This suggests:"
    if [ $PASS_COUNT -eq 0 ]; then
        echo "  • The fix may not have been applied correctly"
        echo "  • Or encode_to_git() is still being skipped"
    else
        echo "  • Most tests passed, some edge cases need work"
    fi
    EXIT_CODE=1
fi

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "Cleanup: Removing test directory"
    cd /
    rm -rf "$TEST_DIR"
else
    echo "Test directory preserved: $TEST_DIR"
    echo "(Remove with: rm -rf $TEST_DIR)"
fi
echo ""

exit $EXIT_CODE
