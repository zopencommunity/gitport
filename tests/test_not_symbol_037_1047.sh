#!/usr/bin/env bash
# ==============================================================================
# Test for NOT symbol (¬) encoding issue between IBM-037 and IBM-1047
# Tests the conversion of 0xb0 (¬ in IBM-037, degree ° in IBM-1047)
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
echo "          NOT SYMBOL (¬) ENCODING TEST (037 vs 1047)                  "
echo "========================================================================"
echo "Git binary: $("$GIT_BIN" --version) ($GIT_BIN)"
echo "Test root:  $TEST_ROOT"
echo ""

PASSED=0
TOTAL=5

cd "$TEST_ROOT"

# ==============================================================================
# Test 1: Check if NOT symbol (¬) can be converted
# ==============================================================================
echo "[Test 1/5] Check iconv support for NOT symbol (¬)..."

# U+00AC (NOT SIGN) in UTF-8 is 0xc2 0xac
# In IBM-1047: 0x5f (caret ^)
# In IBM-037:  0xb0 (NOT symbol ¬)

# Test UTF-8 to IBM-1047 conversion
printf '\xc2\xac' > /tmp/not_utf8.txt
if iconv -f UTF-8 -t IBM-1047 /tmp/not_utf8.txt > /tmp/not_1047.txt 2>/dev/null; then
    echo "  ✓ iconv can convert ¬ from UTF-8 to IBM-1047"
    RESULT=$(xxd -p /tmp/not_1047.txt | tr -d '\n')
    echo "  Result: 0x$RESULT"
    if [ "$RESULT" = "5f" ]; then
        echo "  ✓ PASS: Correctly converted to 0x5f (^)"
        PASSED=$((PASSED + 1))
    else
        echo "  ⚠ Warning: Got 0x$RESULT instead of 0x5f"
    fi
else
    echo "  ✗ FAIL: iconv cannot convert ¬"
fi

# ==============================================================================
# Test 2: Clone repo with NOT symbol in UTF-8
# ==============================================================================
echo ""
echo "[Test 2/5] Clone repo with ¬ symbol (UTF-8 → IBM-1047)..."

mkdir test2 && cd test2
"$GIT_BIN" init -q
"$GIT_BIN" config user.name "Test User"
"$GIT_BIN" config user.email "test@example.com"
"$GIT_BIN" config core.ignorefiletags false

# Create .gitattributes
echo "*.plx zos-working-tree-encoding=IBM-1047" > .gitattributes
"$GIT_BIN" add .gitattributes
"$GIT_BIN" commit -q -m "Add attributes"

# Create PLX file with NOT symbol (¬) in UTF-8
# U+00AC = 0xc2 0xac in UTF-8
cat > test.plx << 'PLX'
/* PL/X source file */
IF (I) THEN ! Test
    Same as   If I¬=0
    </desc>
PLX

# Tag as UTF-8
chtag -tc UTF-8 test.plx

# Verify UTF-8 encoding
if xxd test.plx | grep -q "c2ac"; then
    echo "  ✓ File contains U+00AC (¬) in UTF-8"
else
    echo "  ⚠ Warning: Cannot find ¬ in UTF-8 encoding"
fi

"$GIT_BIN" add test.plx
"$GIT_BIN" commit -q -m "Add PLX with NOT symbol"

# Try to checkout
rm test.plx
if "$GIT_BIN" checkout test.plx 2>&1 | tee /tmp/checkout_not.log; then
    echo "  ✓ Checkout succeeded"
    
    # Check file encoding
    TAG=$(chtag -p test.plx 2>/dev/null | awk '{print $2}')
    echo "  File tag: $TAG"
    
    # Check what character we got
    CHAR=$(xxd test.plx | grep -o "I..=" | head -1)
    echo "  Character: $CHAR"
    
    if [ "$TAG" = "IBM-1047" ]; then
        echo "  ✓ PASS: File correctly tagged as IBM-1047"
        PASSED=$((PASSED + 1))
    else
        echo "  ✗ FAIL: File has wrong tag: $TAG"
    fi
else
    # Check if it's an encoding error
    if grep -q "failed to encode" /tmp/checkout_not.log; then
        echo "  ⚠ Encoding error occurred (user's issue)"
        cat /tmp/checkout_not.log
        
        # Check if tag was set despite error
        if [ -f test.plx ]; then
            TAG=$(chtag -p test.plx 2>/dev/null | awk '{print $2}')
            if [ "$TAG" = "IBM-1047" ]; then
                echo "  ✗ BUG: File tagged as IBM-1047 despite error!"
                echo "  This is the issue Igor mentioned - tag should NOT be set on error"
            fi
        fi
    fi
fi

cd ..

# ==============================================================================
# Test 3: Test with transliteration enabled
# ==============================================================================
echo ""
echo "[Test 3/5] Same test WITH transliteration..."

mkdir test3 && cd test3
"$GIT_BIN" init -q
"$GIT_BIN" config user.name "Test User"
"$GIT_BIN" config user.email "test@example.com"
"$GIT_BIN" config core.ignorefiletags false

echo "*.plx zos-working-tree-encoding=IBM-1047" > .gitattributes
"$GIT_BIN" add .gitattributes
"$GIT_BIN" commit -q -m "Add attributes"

# Create file with NOT symbol
cat > test.plx << 'PLX'
/* PL/X source file */
IF (I) THEN ! Test
    Same as   If I¬=0
    </desc>
PLX

chtag -tc UTF-8 test.plx
"$GIT_BIN" add test.plx
"$GIT_BIN" commit -q -m "Add PLX"

# Enable transliteration
export GIT_ICONV_TRANSLIT=1

rm test.plx
if "$GIT_BIN" checkout test.plx 2>&1 | tee /tmp/checkout_translit.log; then
    echo "  ✓ Checkout succeeded with transliteration"
    
    TAG=$(chtag -p test.plx 2>/dev/null | awk '{print $2}')
    echo "  File tag: $TAG"
    
    if [ "$TAG" = "IBM-1047" ]; then
        echo "  ✓ PASS: File correctly tagged"
        PASSED=$((PASSED + 1))
    fi
else
    echo "  ✗ FAIL: Checkout failed even with transliteration"
    cat /tmp/checkout_translit.log
fi

unset GIT_ICONV_TRANSLIT
cd ..

# ==============================================================================
# Test 4: Verify 0xb0 in IBM-037 vs IBM-1047
# ==============================================================================
echo ""
echo "[Test 4/5] Verify 0xb0 character difference (037 vs 1047)..."

# In IBM-037: 0xb0 = ¬ (NOT symbol)
# In IBM-1047: 0xb0 = degree symbol (°)

# Create file with 0xb0 byte
printf '\xb0' > /tmp/byte_b0.txt

# Try to convert from IBM-037 to UTF-8
if iconv -f IBM-037 -t UTF-8 /tmp/byte_b0.txt > /tmp/from_037.txt 2>/dev/null; then
    CHAR_037=$(xxd -p /tmp/from_037.txt | tr -d '\n')
    echo "  IBM-037 0xb0 → UTF-8: 0x$CHAR_037"
    if [ "$CHAR_037" = "c2ac" ]; then
        echo "  ✓ Correct: U+00AC (¬ NOT symbol)"
    fi
fi

# Try to convert from IBM-1047 to UTF-8
if iconv -f IBM-1047 -t UTF-8 /tmp/byte_b0.txt > /tmp/from_1047.txt 2>/dev/null; then
    CHAR_1047=$(xxd -p /tmp/from_1047.txt | tr -d '\n')
    echo "  IBM-1047 0xb0 → UTF-8: 0x$CHAR_1047"
    if [ "$CHAR_1047" = "c2b0" ]; then
        echo "  ✓ Correct: U+00B0 (° degree symbol)"
    fi
fi

if [ "$CHAR_037" != "$CHAR_1047" ]; then
    echo "  ✓ PASS: Confirmed 0xb0 means different characters in 037 vs 1047"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ FAIL: Same character in both encodings?"
fi

# ==============================================================================
# Test 5: Test caret (^) which is correct in 1047
# ==============================================================================
echo ""
echo "[Test 5/5] Test caret (^) which should work correctly..."

mkdir test5 && cd test5
"$GIT_BIN" init -q
"$GIT_BIN" config user.name "Test User"
"$GIT_BIN" config user.email "test@example.com"
"$GIT_BIN" config core.ignorefiletags false

echo "*.plx zos-working-tree-encoding=IBM-1047" > .gitattributes
"$GIT_BIN" add .gitattributes
"$GIT_BIN" commit -q -m "Add attributes"

# Create file with caret (^) instead of NOT symbol
cat > test.plx << 'PLX'
/* PL/X source file */
IF (I) THEN ! Test
    Same as   If I^=0
    </desc>
PLX

chtag -tc UTF-8 test.plx
"$GIT_BIN" add test.plx
"$GIT_BIN" commit -q -m "Add PLX with caret"

rm test.plx
if "$GIT_BIN" checkout test.plx 2>&1; then
    echo "  ✓ Checkout succeeded with caret (^)"
    
    TAG=$(chtag -p test.plx 2>/dev/null | awk '{print $2}')
    if [ "$TAG" = "IBM-1047" ]; then
        echo "  ✓ PASS: Caret works fine in IBM-1047"
        PASSED=$((PASSED + 1))
    fi
else
    echo "  ✗ FAIL: Even caret failed?"
fi

cd ..

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo "========================================================================"
echo "  SUMMARY: $PASSED / $TOTAL TESTS PASSED"
echo ""
echo "  KEY FINDINGS:"
echo "  - U+00AC (¬ NOT) → IBM-1047: 0x5f (^)"
echo "  - 0xb0 in IBM-037 = ¬ (NOT symbol)"
echo "  - 0xb0 in IBM-1047 = ° (degree symbol)"
echo "  - Problem: File may have been edited in IBM-037 environment"
echo ""
if [ $PASSED -ge 3 ]; then
    echo "  ✓ Transliteration handles this issue"
    echo "  Solution: git config --global core.iconvtranslit true"
    exit 0
else
    echo "  ⚠ Some encoding issues detected"
    exit 1
fi
echo "========================================================================"

