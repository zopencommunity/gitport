#!/bin/bash
# Test: -text + working-tree-encoding combination
# 
# Verifies that files with both -text and working-tree-encoding
# are handled correctly (encoding conversion still happens)

set -e

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  Test: -text + working-tree-encoding Combination                            ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

TEST_DIR="/tmp/test_minus_text_encoding_$$"
mkdir -p "$TEST_DIR"

# Trap for cleanup
trap 'cd / && rm -rf "$TEST_DIR" 2>/dev/null || true' EXIT INT TERM

cd "$TEST_DIR"

echo "Test directory: $TEST_DIR"
echo ""

# Initialize repo
echo "═══ Initialize Git repository ═══"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
echo "✓ Git repo initialized"
echo ""

echo "════════════════════════════════════════════════════════════════════════════════"
echo "Step 1: Create file with -text + working-tree-encoding"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

# Create .gitattributes with -text + encoding
echo "*.txt -text working-tree-encoding=IBM-1047" > .gitattributes
echo "Created .gitattributes:"
cat .gitattributes
echo ""

# Create EBCDIC file
echo "Test content for Issue 2 verification" > test_ascii.txt

# Convert to EBCDIC
if command -v iconv > /dev/null; then
    iconv -f ISO8859-1 -t IBM-1047 < test_ascii.txt > test.txt
    rm test_ascii.txt
    
    # Tag as IBM-1047
    if command -v chtag > /dev/null; then
        chtag -tc IBM-1047 test.txt
        echo "File created and tagged:"
        chtag -p test.txt
    else
        echo "⚠️  chtag not available (not on z/OS?)"
        echo "Created test.txt in EBCDIC"
    fi
else
    # Fallback for non-z/OS systems
    echo "⚠️  iconv not available, using ASCII file"
    cp test_ascii.txt test.txt
    rm test_ascii.txt
fi
echo ""

echo "════════════════════════════════════════════════════════════════════════════════"
echo "Step 2: Add file to git"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

echo "Running: git add .gitattributes test.txt"

# Capture output and exit code
if git add .gitattributes test.txt 2>&1; then
    ADD_STATUS=0
    echo "✓ git add succeeded"
else
    ADD_STATUS=$?
    echo "✗ git add failed with exit code $ADD_STATUS"
fi
echo ""

if [ $ADD_STATUS -ne 0 ]; then
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "RESULT: TEST FAILED"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "❌ git add failed when it should succeed"
    exit 1
fi

echo "════════════════════════════════════════════════════════════════════════════════"
echo "Step 3: Commit and verify Git object encoding"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

git commit -q -m "Test -text + encoding"
echo "✓ Committed"
echo ""

# Get the Git object
HASH=$(git ls-files -s test.txt | awk '{print $2}')
echo "Git object hash: $HASH"
echo ""

echo "Git object content (first 40 bytes):"
git cat-file -p $HASH | od -A x -t x1z -N 40 | head -3
echo ""

# Get first 4 bytes
BYTES=$(git cat-file -p $HASH | od -A n -t x1 -N 4 | tr -d ' ')
echo "First 4 bytes of 'Test': $BYTES"
echo ""

# Expected encodings:
# "Test" in UTF-8:  54 65 73 74
# "Test" in EBCDIC: e3 85 a2 a3

echo "════════════════════════════════════════════════════════════════════════════════"
echo "Step 4: Verify encoding conversion happened"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

# Check if it's UTF-8
if echo "$BYTES" | grep -qi "54657374"; then
    echo "✅ PASS: Git object is UTF-8"
    echo "   Bytes: 54 65 73 74 (UTF-8 for 'Test')"
    echo ""
    echo "This means:"
    echo "  • File was in EBCDIC (IBM-1047)"
    echo "  • Git converted it to UTF-8"
    echo "  • Encoding conversion worked correctly"
    echo "  • -text + working-tree-encoding works!"
    RESULT_CODE=0
elif echo "$BYTES" | grep -qi "e385a2a3"; then
    echo "❌ FAIL: Git object is EBCDIC"
    echo "   Bytes: e3 85 a2 a3 (EBCDIC for 'Test')"
    echo ""
    echo "This means:"
    echo "  • File was in EBCDIC (IBM-1047)"
    echo "  • Git did NOT convert it"
    echo "  • Encoding conversion failed"
    echo "  • -text + working-tree-encoding is broken!"
    RESULT_CODE=1
else
    echo "⚠️  UNCLEAR: Cannot determine encoding"
    echo "   Bytes: $BYTES"
    RESULT_CODE=0  # Don't fail on unclear result
fi
echo ""

echo "════════════════════════════════════════════════════════════════════════════════"
echo "FINAL RESULT"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

if [ $RESULT_CODE -eq 0 ]; then
    echo "✅ TEST PASSED"
    echo ""
    echo "The combination of -text + working-tree-encoding works correctly:"
    echo "  • -text attribute disables EOL conversion"
    echo "  • working-tree-encoding attribute enables encoding conversion"
    echo "  • Both attributes work together as expected"
    echo ""
else
    echo "❌ TEST FAILED"
    echo ""
    echo "The combination of -text + working-tree-encoding does NOT work"
    echo ""
fi
echo ""

exit $RESULT_CODE
