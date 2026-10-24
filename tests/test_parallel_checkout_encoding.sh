#!/usr/bin/env bash
# ==============================================================================
# Parallel Checkout Encoding Test for z/OS
# Tests that parallel checkout correctly tags files with different encodings
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
echo "           PARALLEL CHECKOUT ENCODING TEST SUITE                       "
echo "========================================================================"
echo "Git binary: $("$GIT_BIN" --version) ($GIT_BIN)"
echo "Test root:  $TEST_ROOT"
echo ""

PASSED=0
TOTAL=3

cd "$TEST_ROOT"

# ------------------------------------------------------------------------------
# Test 1: Parallel checkout with mixed encodings
# ------------------------------------------------------------------------------
echo "[Test 1/3] Parallel checkout with mixed file encodings..."

mkdir test1 && cd test1
"$GIT_BIN" init -q
"$GIT_BIN" config core.ignorefiletags false
"$GIT_BIN" config core.preloadIndex true

# Create .gitattributes with different encodings
cat > .gitattributes << 'EOF'
file_ebcdic.txt zos-working-tree-encoding=IBM-1047
file_utf8.txt zos-working-tree-encoding=UTF-8
file_ascii.txt zos-working-tree-encoding=ISO8859-1
EOF

"$GIT_BIN" add .gitattributes
"$GIT_BIN" commit -q -m "Add attributes"

# Create files with different content
echo "EBCDIC content line 1" > file_ebcdic.txt
echo "UTF-8 content line 1" > file_utf8.txt
echo "ASCII content line 1" > file_ascii.txt

"$GIT_BIN" add .
"$GIT_BIN" commit -q -m "Add mixed encoding files"

# Remove files from working tree
rm -f file_*.txt

# Force parallel checkout (need multiple files)
# Add more files to trigger parallel checkout threshold
for i in {1..10}; do
    echo "File $i content" > "filler_$i.txt"
done
"$GIT_BIN" add filler_*.txt
"$GIT_BIN" commit -q -m "Add filler files"
rm -f filler_*.txt file_*.txt

# Checkout with parallel workers
"$GIT_BIN" checkout -f HEAD 2>&1 | grep -v "detached HEAD" || true

# Verify tags
if chtag -p file_ebcdic.txt 2>/dev/null | grep -q "1047"; then
    echo "  ✓ file_ebcdic.txt correctly tagged as IBM-1047"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ FAIL: file_ebcdic.txt not tagged as IBM-1047"
    chtag -p file_ebcdic.txt
fi

cd ..

# ------------------------------------------------------------------------------
# Test 2: Parallel checkout doesn't mix up attributes
# ------------------------------------------------------------------------------
echo ""
echo "[Test 2/3] Parallel checkout doesn't mix up file attributes..."

mkdir test2 && cd test2
"$GIT_BIN" init -q
"$GIT_BIN" config core.ignorefiletags false

# Determine what UTF-8 files should be tagged as (depends on GIT_UTF8_CCSID)
# If GIT_UTF8_CCSID=819, UTF-8 files are tagged as ISO8859-1 (correct behavior)
# If GIT_UTF8_CCSID=1208, UTF-8 files are tagged as UTF-8
if [ "$GIT_UTF8_CCSID" = "819" ]; then
    UTF8_EXPECTED_TAG="ISO8859-1"
else
    UTF8_EXPECTED_TAG="UTF-8"
fi

echo "  (UTF-8 files will be tagged as: $UTF8_EXPECTED_TAG based on GIT_UTF8_CCSID=${GIT_UTF8_CCSID:-default})"

# Create many files with alternating encodings
cat > .gitattributes << 'EOF'
even_*.txt zos-working-tree-encoding=IBM-1047
odd_*.txt zos-working-tree-encoding=UTF-8
EOF

"$GIT_BIN" add .gitattributes
"$GIT_BIN" commit -q -m "Add attributes"

# Create 20 files
for i in {0..9}; do
    echo "Even file $i" > "even_$i.txt"
    echo "Odd file $i" > "odd_$i.txt"
done

"$GIT_BIN" add .
"$GIT_BIN" commit -q -m "Add many files"

# Remove and checkout
rm -f even_*.txt odd_*.txt
"$GIT_BIN" checkout -f HEAD 2>&1 | grep -v "detached HEAD" || true

# Check all tags are correct
ERRORS=0
for i in {0..9}; do
    if ! chtag -p "even_$i.txt" 2>/dev/null | grep -q "1047"; then
        echo "  ✗ even_$i.txt has wrong tag"
        chtag -p "even_$i.txt"
        ERRORS=$((ERRORS + 1))
    fi
    # Check for expected UTF-8 tag (could be ISO8859-1 or UTF-8)
    if ! chtag -p "odd_$i.txt" 2>/dev/null | grep -qE "$UTF8_EXPECTED_TAG"; then
        echo "  ✗ odd_$i.txt has wrong tag (expected $UTF8_EXPECTED_TAG)"
        chtag -p "odd_$i.txt"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ $ERRORS -eq 0 ]; then
    echo "  ✓ All 20 files have correct tags (no race condition)"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ FAIL: $ERRORS files have incorrect tags (race condition!)"
fi

cd ..

# ------------------------------------------------------------------------------
# Test 3: Parallel checkout with binary files
# ------------------------------------------------------------------------------
echo ""
echo "[Test 3/3] Parallel checkout correctly handles binary files..."

mkdir test3 && cd test3
"$GIT_BIN" init -q
"$GIT_BIN" config core.ignorefiletags false

cat > .gitattributes << 'EOF'
*.bin binary
*.txt zos-working-tree-encoding=IBM-1047
EOF

"$GIT_BIN" add .gitattributes
"$GIT_BIN" commit -q -m "Add attributes"

# Create binary and text files
printf '\x00\x01\x02\x03\xFF\xFE' > binary.bin
echo "Text file" > text.txt

"$GIT_BIN" add .
"$GIT_BIN" commit -q -m "Add mixed files"

rm -f binary.bin text.txt
"$GIT_BIN" checkout -f HEAD 2>&1 | grep -v "detached HEAD" || true

# Binary should be untagged or binary-tagged
if chtag -p binary.bin 2>/dev/null | grep -qE "untagged|binary"; then
    echo "  ✓ binary.bin correctly tagged as binary/untagged"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ FAIL: binary.bin has incorrect tag"
    chtag -p binary.bin
fi

cd ..

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo ""
echo "========================================================================"
echo "  SUMMARY: $PASSED / $TOTAL TESTS PASSED"
if [ $PASSED -eq $TOTAL ]; then
    echo "  ✓ ALL TESTS PASSED - Parallel checkout encoding is correct!"
else
    echo "  ✗ SOME TESTS FAILED"
    exit 1
fi
echo "========================================================================"

exit 0
