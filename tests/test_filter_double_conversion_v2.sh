#!/bin/bash
# Test: Does Git double-convert filter output on z/OS? (CORRECTED VERSION)
# Purpose: Verify P1's bug vs patch author's "double conversion" concern

set -e

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║     Test: Filter Output Conversion on z/OS (v2 - CORRECTED)                  ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Create test directory
TEST_DIR="/tmp/git_filter_test_v2_$$"

# Trap to ensure cleanup on exit
trap 'cd / && rm -rf "$TEST_DIR" 2>/dev/null || true' EXIT INT TERM
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo "Test directory: $TEST_DIR"
echo ""

# Initialize Git repo
echo "═══ Step 1: Initialize Git repository ═══"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
echo "✓ Git repo initialized"
echo ""

# Create simple cat filter
echo "═══ Step 2: Create pass-through filter ═══"
cat > filter.sh << 'FILTER'
#!/bin/bash
# This filter does NO conversion - just passes data through
cat
FILTER
chmod +x filter.sh

git config filter.testfilter.clean "$(pwd)/filter.sh"
git config filter.testfilter.smudge "$(pwd)/filter.sh"
git config filter.testfilter.required true

echo "Filter configured: cat (pass-through)"
echo "✓ Filter script created"
echo ""

# Create .gitattributes
echo "═══ Step 3: Configure .gitattributes ═══"
cat > .gitattributes << 'ATTR'
*.txt filter=testfilter working-tree-encoding=IBM-1047
ATTR

echo "Attributes set: filter=testfilter working-tree-encoding=IBM-1047"
echo "✓ .gitattributes created"
echo ""

# Create ACTUAL EBCDIC test file (CORRECTED!)
echo "═══ Step 4: Create ACTUAL EBCDIC test file ═══"
echo "Creating UTF-8 source first..."
echo "Hello from EBCDIC filter test!" > test_utf8.txt

echo "Converting to EBCDIC..."
iconv -f UTF-8 -t IBM-1047 test_utf8.txt > test.txt

echo "Tagging as IBM-1047..."
chtag -tc IBM-1047 test.txt

echo ""
echo "File: test.txt"
ls -l test.txt
echo -n "Tag: "
chtag -p test.txt
echo ""

# Show file content
echo "File content (hex dump - should be EBCDIC now!):"
od -A x -t x1z -N 32 test.txt
echo ""

# Expected bytes
echo "Reference encodings:"
echo "  UTF-8 'Hello':   48 65 6c 6c 6f"
echo "  EBCDIC 'Hello':  c8 85 93 93 96"
echo ""

# Verify it's actually EBCDIC
FIRST_BYTES=$(od -A n -t x1 -N 5 test.txt | tr -d ' \n')
if echo "$FIRST_BYTES" | grep -qi "^c88593939"; then
    echo "✓ Confirmed: File contains EBCDIC bytes"
elif echo "$FIRST_BYTES" | grep -qi "^48656c6c6"; then
    echo "✗ ERROR: File still contains UTF-8 bytes!"
    echo "  This means iconv didn't work or file got reconverted"
    exit 1
else
    echo "⚠️  WARNING: Unexpected bytes: $FIRST_BYTES"
fi
echo ""

# Add file to Git
echo "═══ Step 5: Add file to Git (triggers filter + conversion) ═══"
echo ""
echo "What SHOULD happen:"
echo "  1. Git reads EBCDIC file: 'c8 85 93 93 96...' (Hello in EBCDIC)"
echo "  2. Filter runs: outputs same EBCDIC (cat filter)"
echo "  3. encode_to_git() converts: EBCDIC → UTF-8"
echo "  4. Git stores: '48 65 6c 6c 6f...' (Hello in UTF-8)"
echo ""
echo "With CURRENT z/OS patch (#ifdef __MVS__ skip):"
echo "  1. Git reads EBCDIC file: 'c8 85 93 93 96...'"
echo "  2. Filter runs: outputs EBCDIC"
echo "  3. encode_to_git() SKIPPED"
echo "  4. Git stores EBCDIC 'c8 85 93 93 96...' ❌ (P1's bug!)"
echo ""

git add test.txt
echo "✓ File added"
echo ""

# Check Git object
echo "═══ Step 6: Examine Git object ═══"
HASH=$(git ls-files -s test.txt | awk '{print $2}')
echo "Object hash: $HASH"
echo ""

echo "Git object content (hex dump):"
git cat-file -p $HASH | od -A x -t x1z -N 32
echo ""

# Analysis
echo "═══ Step 7: Analysis ═══"
echo ""

# Get first 5 bytes
OBJECT_HEX=$(git cat-file -p $HASH | od -A n -t x1 -N 5 | tr -d ' \n')
echo "First 5 bytes of Git object: $OBJECT_HEX"
echo ""

# Determine encoding
if echo "$OBJECT_HEX" | grep -qi "^48656c6c6f"; then
    echo "✅ RESULT: Git object contains UTF-8"
    echo ""
    echo "   Bytes match UTF-8 'Hello': 48 65 6c 6c 6f"
    echo ""
    echo "   CONCLUSION:"
    echo "   • encode_to_git() IS being called"
    echo "   • Conversion EBCDIC → UTF-8 happened correctly"
    echo "   • Git object is correct ✓"
    echo ""
    echo "   This means:"
    echo "   • The #ifdef __MVS__ is NOT preventing conversion"
    echo "   • OR there's another code path being used"
    echo "   • OR the condition isn't being triggered"
    echo ""
    echo "   RECOMMENDATION:"
    echo "   • The current behavior is CORRECT"
    echo "   • P1's bug does NOT exist (or is already fixed)"
    echo "   • No change needed to convert.c"
    RESULT="UTF-8"
    EXIT_CODE=0
elif echo "$OBJECT_HEX" | grep -qi "^c885939396"; then
    echo "❌ RESULT: Git object contains EBCDIC"
    echo ""
    echo "   Bytes match EBCDIC 'Hello': c8 85 93 93 96"
    echo ""
    echo "   CONCLUSION:"
    echo "   • encode_to_git() was SKIPPED"
    echo "   • No conversion happened"
    echo "   • Git object stores EBCDIC ✗"
    echo ""
    echo "   This confirms:"
    echo "   • P1's bug is REAL and ACTIVE"
    echo "   • The #ifdef __MVS__ patch IS preventing conversion"
    echo "   • Repository corruption is happening!"
    echo ""
    echo "   RECOMMENDATION:"
    echo "   • REMOVE the #ifdef __MVS__ block from convert.c:1612-1626"
    echo "   • This will restore encode_to_git() call"
    echo "   • Will fix repository corruption"
    RESULT="EBCDIC"
    EXIT_CODE=1
else
    echo "⚠️  RESULT: Unexpected encoding"
    echo ""
    echo "   Bytes don't match UTF-8 or EBCDIC"
    echo "   Actual: $OBJECT_HEX"
    echo ""
    echo "   This suggests:"
    echo "   • Unexpected conversion occurred"
    echo "   • Or file content was altered"
    echo "   • Need manual investigation"
    RESULT="UNKNOWN"
    EXIT_CODE=2
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# Summary
echo "SUMMARY:"
echo "════════════════════════════════════════════════════════════════════════════════"
echo "Test setup:     ACTUAL EBCDIC file + cat filter + working-tree-encoding=IBM-1047"
echo "Git object:     $RESULT"
echo ""

echo "Exit code: $EXIT_CODE"
echo "  0 = UTF-8 (correct behavior, fix is working)"
echo "  1 = EBCDIC (P1's bug, need to fix)"
echo "  2 = Unknown (need investigation)"
echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "Cleanup: Removing test directory"
    cd /
    rm -rf "$TEST_DIR"
else
    echo "Cleanup: Keeping test directory for inspection"
    echo "Directory: $TEST_DIR"
    echo ""
    echo "(Remove manually with: rm -rf $TEST_DIR)"
fi

exit $EXIT_CODE

