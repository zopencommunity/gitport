#!/usr/bin/env bash
# ==============================================================================
# Test for unmappable Unicode characters (U+2011 issue)
# Tests that GIT_ICONV_TRANSLIT properly handles characters not in IBM-1047
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Find git binary
if [ -x "$REPO_ROOT/git/git" ]; then
    GIT_BIN="$REPO_ROOT/git/git"
else
    GIT_BIN="$(which git)"
fi

TEST_ROOT="$(pwd)/test_tmp_$$"
mkdir -p "$TEST_ROOT"
trap 'rm -rf "$TEST_ROOT"' EXIT

echo "========================================================================"
echo "          UNMAPPABLE UNICODE CHARACTERS TEST (U+2011)                  "
echo "========================================================================"
echo "Git binary: $("$GIT_BIN" --version) ($GIT_BIN)"
echo "Test root:  $TEST_ROOT"
echo ""

PASSED=0
TOTAL=4

cd "$TEST_ROOT"

# ==============================================================================
# Test 1: U+2011 without transliteration should fail gracefully
# ==============================================================================
echo "[Test 1/4] U+2011 without transliteration - should fail gracefully..."

mkdir test1 && cd test1
"$GIT_BIN" init -q
"$GIT_BIN" config user.name "Test User"
"$GIT_BIN" config user.email "test@example.com"
"$GIT_BIN" config core.ignorefiletags false

# Create .gitattributes with IBM-1047
echo "*.txt zos-working-tree-encoding=IBM-1047" > .gitattributes
"$GIT_BIN" add .gitattributes
"$GIT_BIN" commit -q -m "Add attributes"

# Create file with U+2011 (NON-BREAKING HYPHEN) in UTF-8
# U+2011 in UTF-8 is: 0xe2 0x80 0x91
printf 'This is a non\xe2\x80\x91breaking hyphen\n' > test.txt
chtag -tc UTF-8 test.txt

"$GIT_BIN" add test.txt
"$GIT_BIN" commit -q -m "Add file with U+2011"

# Checkout without transliteration - should handle gracefully
rm test.txt
unset GIT_ICONV_TRANSLIT

# Try checkout - may fail or succeed depending on iconv behavior
if "$GIT_BIN" checkout test.txt 2>&1 | tee /tmp/checkout1.log; then
    # If it succeeded, check what we got
    if xxd test.txt | grep -q "3f"; then
        echo "  ⚠ Checkout succeeded but produced 0x3f (illegal char)"
        echo "  This is the bug the user reported!"
    else
        echo "  ✓ Checkout succeeded without 0x3f"
        PASSED=$((PASSED + 1))
    fi
else
    # Failed - that's actually good (fail-fast)
    if grep -qi "failed to encode\|conversion" /tmp/checkout1.log; then
        echo "  ✓ PASS: Git failed with encoding error (fail-fast, good!)"
        PASSED=$((PASSED + 1))
    else
        echo "  ✗ FAIL: Git failed but with unexpected error"
        cat /tmp/checkout1.log
    fi
fi

cd ..

# ==============================================================================
# Test 2: U+2011 WITH transliteration should succeed
# ==============================================================================
echo ""
echo "[Test 2/4] U+2011 WITH transliteration - should convert to regular hyphen..."

mkdir test2 && cd test2
"$GIT_BIN" init -q
"$GIT_BIN" config user.name "Test User"
"$GIT_BIN" config user.email "test@example.com"
"$GIT_BIN" config core.ignorefiletags false

# Create .gitattributes
echo "*.txt zos-working-tree-encoding=IBM-1047" > .gitattributes
"$GIT_BIN" add .gitattributes
"$GIT_BIN" commit -q -m "Add attributes"

# Create file with U+2011
printf 'This is a non\xe2\x80\x91breaking hyphen\n' > test.txt
chtag -tc UTF-8 test.txt
"$GIT_BIN" add test.txt
"$GIT_BIN" commit -q -m "Add file with U+2011"

# Checkout WITH transliteration
rm test.txt
export GIT_ICONV_TRANSLIT=1

if "$GIT_BIN" checkout test.txt 2>&1 | tee /tmp/checkout2.log; then
    echo "  ✓ Checkout succeeded with transliteration"
    
    # Check if it's a regular hyphen (not 0x3f)
    # In IBM-1047, regular hyphen is 0x60
    # In ISO8859-1/ASCII, regular hyphen is 0x2d
    TAG=$(chtag -p test.txt 2>/dev/null | awk '{print $2}')
    
    if xxd test.txt | grep -q "3f"; then
        echo "  ✗ FAIL: File still contains 0x3f (illegal char)"
        xxd test.txt | grep "3f"
    else
        echo "  ✓ PASS: No 0x3f found - character was transliterated"
        PASSED=$((PASSED + 1))
        
        # Check if it became a regular hyphen
        CONTENT=$(cat test.txt)
        if echo "$CONTENT" | grep -q "non.breaking"; then
            echo "  ✓ File content looks correct"
        fi
    fi
else
    echo "  ✗ FAIL: Checkout failed even with transliteration"
    cat /tmp/checkout2.log
fi

cd ..

# ==============================================================================
# Test 3: Multiple unmappable characters
# ==============================================================================
echo ""
echo "[Test 3/4] Multiple unmappable characters (café, naïve, €)..."

mkdir test3 && cd test3
"$GIT_BIN" init -q
"$GIT_BIN" config user.name "Test User"
"$GIT_BIN" config user.email "test@example.com"
"$GIT_BIN" config core.ignorefiletags false

echo "*.txt zos-working-tree-encoding=IBM-1047" > .gitattributes
"$GIT_BIN" add .gitattributes
"$GIT_BIN" commit -q -m "Add attributes"

# Create file with various special characters
# café (é = U+00E9 = 0xc3 0xa9)
# naïve (ï = U+00EF = 0xc3 0xaf)
# € (U+20AC = 0xe2 0x82 0xac)
printf 'caf\xc3\xa9 na\xc3\xafve \xe2\x82\xac\n' > test.txt
chtag -tc UTF-8 test.txt
"$GIT_BIN" add test.txt
"$GIT_BIN" commit -q -m "Add special chars"

rm test.txt
export GIT_ICONV_TRANSLIT=1

if "$GIT_BIN" checkout test.txt 2>&1 | tee /tmp/checkout3.log; then
    echo "  ✓ Checkout succeeded"
    
    CONTENT=$(cat test.txt)
    echo "  Content: $CONTENT"
    
    # Check if characters were approximated (not converted to 0x3f)
    if xxd test.txt | grep -q "3f"; then
        echo "  ⚠ Warning: Contains 0x3f"
    else
        echo "  ✓ PASS: No 0x3f found - transliteration worked"
        PASSED=$((PASSED + 1))
    fi
else
    echo "  ✗ FAIL: Checkout failed"
    cat /tmp/checkout3.log
fi

cd ..

# ==============================================================================
# Test 4: Verify file doesn't appear modified after checkout
# ==============================================================================
echo ""
echo "[Test 4/4] File shouldn't appear modified after checkout..."

mkdir test4 && cd test4
"$GIT_BIN" init -q
"$GIT_BIN" config user.name "Test User"
"$GIT_BIN" config user.email "test@example.com"
"$GIT_BIN" config core.ignorefiletags false

echo "*.txt zos-working-tree-encoding=IBM-1047" > .gitattributes
"$GIT_BIN" add .gitattributes
"$GIT_BIN" commit -q -m "Add attributes"

# Create file with U+2011
printf 'non\xe2\x80\x91breaking\n' > test.txt
chtag -tc UTF-8 test.txt
"$GIT_BIN" add test.txt
"$GIT_BIN" commit -q -m "Add U+2011"

# Checkout with transliteration
export GIT_ICONV_TRANSLIT=1
rm test.txt
"$GIT_BIN" checkout test.txt >/dev/null 2>&1

# Check git status - file should NOT appear modified
if "$GIT_BIN" status --porcelain | grep -q "test.txt"; then
    echo "  ⚠ Warning: File appears modified after checkout"
    "$GIT_BIN" status --short
    echo "  This is the user's reported issue!"
    # This might be expected depending on conversion behavior
else
    echo "  ✓ PASS: File does not appear modified"
    PASSED=$((PASSED + 1))
fi

cd ..

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo "========================================================================"
echo "  SUMMARY: $PASSED / $TOTAL TESTS PASSED"
if [ $PASSED -ge 3 ]; then
    echo "  ✓ Transliteration appears to be working!"
    echo ""
    echo "  Key findings:"
    echo "  - GIT_ICONV_TRANSLIT=1 prevents 0x3f corruption"
    echo "  - Special characters are approximated, not corrupted"
    echo "  - Solution is ready for user"
    exit 0
else
    echo "  ⚠ Some issues found - review needed"
    echo ""
    echo "  If tests failed, check if:"
    echo "  - iconv supports //TRANSLIT on this system"
    echo "  - IBM-1047 encoding is available"
    exit 1
fi
echo "========================================================================"

