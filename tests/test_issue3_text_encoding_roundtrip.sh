#!/bin/bash
# Test Issue 3: -text + working-tree-encoding round-trip
#
# This test verifies that files with -text attribute AND working-tree-encoding
# properly round-trip through add and checkout.
#
# Bug: Checkout direction skips encoding conversion when attr_action == CRLF_BINARY,
# causing phantom modifications.

set -e

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║     Test: Issue 3 - Text + Encoding Round-trip                               ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

TEST_DIR="/tmp/git_issue3_test_$$"
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

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "Step 1: Create file with -text + encoding"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# Create .gitattributes
echo "*.txt -text working-tree-encoding=ISO-8859-1" > .gitattributes
echo "Created .gitattributes:"
cat .gitattributes
echo ""

# Create Latin-1 file with special character (é = 0xe9 in Latin-1)
echo "Café - Testing Issue 3" > test_utf8.txt
echo "UTF-8 source file created"

# Convert to Latin-1
if command -v iconv > /dev/null; then
    iconv -f UTF-8 -t ISO-8859-1 test_utf8.txt > test.txt
    rm test_utf8.txt
    echo "✓ Converted to ISO-8859-1 (Latin-1)"
else
    # Fallback: create simple ASCII file
    echo "Cafe - Testing Issue 3" > test.txt
    echo "⚠️  iconv not available, using ASCII file"
fi

echo ""
echo "Original file content:"
od -A x -t x1z -N 30 test.txt | head -3
echo ""

# Capture original bytes
ORIGINAL_BYTES=$(od -A n -t x1 test.txt | tr -d ' \n')
echo "Original bytes (hex): ${ORIGINAL_BYTES:0:40}..."
echo ""

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "Step 2: Add and commit"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

git add .gitattributes test.txt
git commit -q -m "Initial commit: Latin-1 file with -text"
echo "✓ Committed"
echo ""

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "Step 3: Verify Git object (should be UTF-8)"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

HASH=$(git ls-files -s test.txt | awk '{print $2}')
echo "Git object hash: $HASH"
echo ""
echo "Git object content (should be UTF-8):"
git cat-file -p $HASH | od -A x -t x1z -N 30 | head -3
echo ""

OBJECT_HEX=$(git cat-file -p $HASH | od -A n -t x1 -N 10 | tr -d ' \n')
echo "Object bytes (first 10): $OBJECT_HEX"
echo ""

# Check if it's UTF-8 (Café in UTF-8 has c3 a9 for é)
if echo "$OBJECT_HEX" | grep -q "c3a9"; then
    echo "✓ Git object contains UTF-8 (found c3a9 for é)"
elif echo "$OBJECT_HEX" | grep -q "e9"; then
    echo "⚠️  Git object might still contain Latin-1 (found e9 for é)"
else
    echo "ℹ  Object encoding unclear (no special chars or ASCII only)"
fi
echo ""

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "Step 4: Checkout fresh (should convert back to Latin-1)"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

rm test.txt
git checkout test.txt
echo "✓ Checked out"
echo ""

echo "After checkout:"
od -A x -t x1z -N 30 test.txt | head -3
echo ""

# Capture after bytes
AFTER_BYTES=$(od -A n -t x1 test.txt | tr -d ' \n')
echo "After bytes (hex): ${AFTER_BYTES:0:40}..."
echo ""

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "Step 5: Verify round-trip"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

EXIT_CODE=0

echo "Comparison:"
echo "  Original: ${ORIGINAL_BYTES:0:40}..."
echo "  After:    ${AFTER_BYTES:0:40}..."
echo ""

if [ "$ORIGINAL_BYTES" = "$AFTER_BYTES" ]; then
    echo "✅ PASS: Bytes match exactly!"
    echo "   Round-trip successful: Latin-1 → UTF-8 → Latin-1"
    echo ""
else
    echo "❌ FAIL: Bytes don't match!"
    echo "   Round-trip broken: File encoding changed"
    echo ""
    
    # Detailed comparison for first difference
    for i in $(seq 0 2 $((${#ORIGINAL_BYTES} - 2))); do
        ORIG_BYTE="${ORIGINAL_BYTES:$i:2}"
        AFTER_BYTE="${AFTER_BYTES:$i:2}"
        if [ "$ORIG_BYTE" != "$AFTER_BYTE" ]; then
            POS=$((i / 2))
            echo "   First difference at byte $POS:"
            echo "     Original: 0x$ORIG_BYTE"
            echo "     After:    0x$AFTER_BYTE"
            break
        fi
    done
    echo ""
    EXIT_CODE=1
fi

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "Step 6: Check for phantom modification"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

echo "Running: git status --porcelain"
STATUS_OUTPUT=$(git status --porcelain)

if [ -z "$STATUS_OUTPUT" ]; then
    echo "✅ PASS: git status shows clean"
    echo "   No phantom modification"
    echo ""
elif echo "$STATUS_OUTPUT" | grep -q "test.txt"; then
    echo "❌ FAIL: git status shows test.txt modified"
    echo "   Phantom modification detected!"
    echo ""
    echo "   Status output:"
    git status --short
    echo ""
    echo "   This means checkout didn't properly convert back to Latin-1"
    echo "   File is now in wrong encoding (likely UTF-8 instead of Latin-1)"
    EXIT_CODE=1
else
    echo "ℹ  Status shows other changes (not test.txt)"
    git status --short
    echo ""
fi

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "RESULT"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ ALL CHECKS PASSED"
    echo ""
    echo "Issue 3 is FIXED:"
    echo "  • Round-trip successful (bytes match)"
    echo "  • No phantom modification (git status clean)"
    echo "  • -text + working-tree-encoding works correctly"
    echo ""
    echo "The fix is working: encode_to_worktree() respects encoding"
else
    echo "❌ TEST FAILED"
    echo ""
    echo "Issue 3 is NOT FIXED:"
    echo "  • Round-trip broken (bytes changed)"
    echo "  • OR phantom modification (git status shows modified)"
    echo "  • -text + working-tree-encoding doesn't work"
    echo ""
    echo "Required fix in git/convert.c line 540:"
    echo "  Change: if (attr_action == CRLF_BINARY) {"
    echo "  To:     if (attr_action == CRLF_BINARY && !enc) {"
fi

echo ""
exit $EXIT_CODE
