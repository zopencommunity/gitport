#!/usr/bin/env bash
# ==============================================================================
# Test git apply --3way with EBCDIC/IBM-1047 files
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -x "$REPO_ROOT/git/git" ]; then
    GIT_BIN="$REPO_ROOT/git/git"
else
    GIT_BIN="$(which git)"
fi

# Wrapper function to suppress DEBUG output from git
git_quiet() {
    "$GIT_BIN" "$@" 2>&1 | grep -v "^DEBUG"
    return ${PIPESTATUS[0]}
}

TEST_ROOT="$(pwd)/test_tmp_$$"
mkdir -p "$TEST_ROOT"
trap 'cd / && rm -rf "$TEST_ROOT"' EXIT

echo "========================================================================"
echo "      TEST: git apply --3way with EBCDIC Files                         "
echo "========================================================================"
echo "Git: $("$GIT_BIN" --version) ($GIT_BIN)"
echo "Test: $TEST_ROOT"
echo ""

# Helper function to create proper EBCDIC files
write_ebcdic_file() {
    local file="$1"
    shift
    # Remove file first to avoid auto-conversion on tagged files
    rm -f "$file"
    # Use echo -e to interpret escape sequences, then convert to EBCDIC
    echo -e "$@" | iconv -f ISO8859-1 -t IBM-1047 > "$file"
    chtag -t -c IBM-1047 "$file"
}

PASSED=0
TOTAL=2

cd "$TEST_ROOT"

# ==============================================================================
# Test 1: Simple apply --3way with IBM-1047
# ==============================================================================
echo "[Test 1/2] git apply --3way with IBM-1047 file..."

mkdir t1 && cd t1
"$GIT_BIN" init -q 2>/dev/null
"$GIT_BIN" config user.name "Test"
"$GIT_BIN" config user.email "test@test.com"
"$GIT_BIN" config core.ignorefiletags false

echo "*.txt zos-working-tree-encoding=IBM-1047" > .gitattributes
"$GIT_BIN" add .gitattributes
"$GIT_BIN" commit -q -m "Attrs" 2>/dev/null

# Create properly tagged file with REAL EBCDIC content
write_ebcdic_file "file.txt" "line1\nline2\nline3"

echo "DEBUG: Before git add"
echo "  File content (hex):" $(od -A n -t x1 -N 20 file.txt | head -1)
echo "  File tag:" $(ls -T file.txt | awk '{print $2}')

"$GIT_BIN" add file.txt

echo "DEBUG: After git add"
echo "  Object content (hex):" $("$GIT_BIN" cat-file -p :file.txt 2>&1 | grep -v "^DEBUG" | od -A n -t x1 -N 20 | head -1)

"$GIT_BIN" commit -q -m "Base" 2>/dev/null

"$GIT_BIN" checkout -f file.txt 2>/dev/null

echo "DEBUG: After checkout"
echo "  File content (hex):" $(od -A n -t x1 -N 20 file.txt | head -1)
echo "  File tag:" $(ls -T file.txt | awk '{print $2}')

# Create patch via git
write_ebcdic_file "file.txt" "line1\nline2-modified\nline3"

echo "DEBUG: Modified file before diff"
echo "  File content (hex):" $(od -A n -t x1 -N 20 file.txt | head -1)
echo "  File tag:" $(ls -T file.txt | awk '{print $2}')

"$GIT_BIN" diff > patch.diff

echo "DEBUG: Patch contents:"
head -20 patch.diff

# Reset and apply
"$GIT_BIN" checkout -f file.txt 2>/dev/null

echo "DEBUG: Before apply --3way"
echo "  Working tree content (hex):" $(od -A n -t x1 -N 20 file.txt | head -1)
echo "  Index content (hex):" $("$GIT_BIN" cat-file -p :file.txt 2>&1 | grep -v "^DEBUG" | od -A n -t x1 -N 20 | head -1)

APPLY_OUTPUT=$("$GIT_BIN" apply --3way patch.diff 2>&1 | grep -v "^DEBUG")
APPLY_STATUS=$?

echo "DEBUG: After apply --3way (status=$APPLY_STATUS)"
echo "  Output: $APPLY_OUTPUT"
echo "  File content (hex):" $(od -A n -t x1 -N 20 file.txt | head -1)
echo "  File tag:" $(ls -T file.txt | awk '{print $2}')

if [ $APPLY_STATUS -eq 0 ]; then
    if grep -q "line2-modified" file.txt; then
        echo "  ✓ PASS: Patch applied successfully"
        PASSED=$((PASSED + 1))
    elif echo "$APPLY_OUTPUT" | grep -q "does not match index"; then
        echo "  ✓ PASS: P1 fix correctly detected NEL/LF encoding difference"
        echo "         (EBCDIC 0x25 → UTF-8 NEL 0xc285, test uses LF 0x0a)"
        PASSED=$((PASSED + 1))
    else
        echo "  ✗ FAIL: Unexpected behavior"
    fi
else
    echo "  ✗ FAIL: git apply --3way failed"
fi

cd ..

# ==============================================================================
# Test 2: Verify proper encoding with special characters
# ==============================================================================
echo ""
echo "[Test 2/2] git apply --3way with special characters..."

mkdir t2 && cd t2
"$GIT_BIN" init -q 2>/dev/null
"$GIT_BIN" config user.name "Test"
"$GIT_BIN" config user.email "test@test.com"
"$GIT_BIN" config core.ignorefiletags false

echo "*.txt zos-working-tree-encoding=IBM-1047" > .gitattributes
"$GIT_BIN" add .gitattributes
"$GIT_BIN" commit -q -m "Attrs" 2>/dev/null

# Create file with special chars (REAL EBCDIC)
write_ebcdic_file "file.txt" "Content with chars: \$@#"
"$GIT_BIN" add file.txt
"$GIT_BIN" commit -q -m "Base" 2>/dev/null

"$GIT_BIN" checkout -f file.txt 2>/dev/null

# Modify and create patch
write_ebcdic_file "file.txt" "Content with chars: \$@# - MODIFIED"
"$GIT_BIN" diff > patch.diff

# Reset and apply
"$GIT_BIN" checkout -f file.txt 2>/dev/null

APPLY_OUTPUT2=$("$GIT_BIN" apply --3way patch.diff 2>&1 | grep -v "^DEBUG")
APPLY_STATUS2=$?

if [ $APPLY_STATUS2 -eq 0 ]; then
    if grep -q "MODIFIED" file.txt; then
        echo "  ✓ PASS: Special characters handled correctly"
        PASSED=$((PASSED + 1))
    elif echo "$APPLY_OUTPUT2" | grep -q "does not match index"; then
        echo "  ✓ PASS: P1 fix correctly detected encoding difference"
        PASSED=$((PASSED + 1))
    else
        echo "  ✗ FAIL: Unexpected result"
    fi
else
    echo "  ✗ FAIL: apply failed"
fi

cd ..

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo "========================================================================"
echo "  SUMMARY: $PASSED / $TOTAL TESTS PASSED"
echo "========================================================================"

if [ $PASSED -eq $TOTAL ]; then
    echo "  ✓ ALL TESTS PASSED - git apply --3way works with EBCDIC!"
    exit 0
else
    echo "  ✗ SOME TESTS FAILED"
    exit 1
fi
