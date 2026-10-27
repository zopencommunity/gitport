#!/bin/bash
# Test: Does Git double-convert filter output on z/OS?
# Purpose: Verify P1's bug vs patch author's "double conversion" concern

set -e

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║     Test: Filter Output Conversion on z/OS                                    ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Create test directory
TEST_DIR="/tmp/git_filter_test_$$"
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
# If input is EBCDIC, output is EBCDIC
# If input is UTF-8, output is UTF-8
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

# Create EBCDIC test file
echo "═══ Step 4: Create EBCDIC test file ═══"
echo "Hello from EBCDIC filter test!" > test.txt
chtag -tc IBM-1047 test.txt

echo "File: test.txt"
ls -l test.txt
echo -n "Tag: "
chtag -p test.txt
echo ""

# Show file content
echo "File content (hex dump):"
od -A x -t x1z -N 32 test.txt
echo ""

# Expected bytes for "Hello"
echo "Reference encodings:"
echo "  UTF-8 'Hello':   48 65 6c 6c 6f"
echo "  EBCDIC 'Hello':  c8 85 93 93 96"
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
echo "  1. Git reads EBCDIC file"
echo "  2. Filter runs: outputs EBCDIC"
echo "  3. encode_to_git() SKIPPED"
echo "  4. Git stores EBCDIC ❌ (P1's bug!)"
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
    echo "   • Conversion EBCDIC → UTF-8 happened"
    echo "   • Git object is correct ✓"
    echo ""
    echo "   This means:"
    echo "   • The #ifdef __MVS__ might not be effective"
    echo "   • OR there's another conversion path"
    echo "   • Need to investigate code flow"
    RESULT="UTF-8"
elif echo "$OBJECT_HEX" | grep -qi "^c88593939"; then
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
    echo "   • P1's bug is REAL"
    echo "   • The patch CREATES the bug"
    echo "   • Must remove #ifdef __MVS__ skip"
    RESULT="EBCDIC"
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
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# Summary
echo "SUMMARY:"
echo "════════════════════════════════════════════════════════════════════════════════"
echo "Test setup:     EBCDIC file + cat filter + working-tree-encoding=IBM-1047"
echo "Git object:     $RESULT"
echo ""

if [ "$RESULT" = "UTF-8" ]; then
    echo "Recommendation: Investigate why conversion happens despite #ifdef __MVS__"
    echo "                May need to check if there's another code path"
    EXIT_CODE=0
elif [ "$RESULT" = "EBCDIC" ]; then
    echo "Recommendation: REMOVE #ifdef __MVS__ block from convert.c:1612-1626"
    echo "                This will restore correct encode_to_git() behavior"
    EXIT_CODE=1
else
    echo "Recommendation: Manual investigation needed"
    EXIT_CODE=2
fi

echo ""
echo "Cleanup: Keeping test directory for inspection"
echo "Directory: $TEST_DIR"
echo ""
echo "(Remove manually with: rm -rf $TEST_DIR)"

exit $EXIT_CODE

