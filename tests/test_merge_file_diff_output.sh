#!/usr/bin/env bash
# ==============================================================================
# Test git merge-file and git diff --output file tagging
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -x "$REPO_ROOT/git/git" ]; then
    GIT_BIN="$REPO_ROOT/git/git"
else
    GIT_BIN="$(which git)"
fi

TEST_ROOT="$(pwd)/test_tmp_$$"
mkdir -p "$TEST_ROOT"
trap 'rm -rf "$TEST_ROOT"' EXIT

echo "========================================================================"
echo "      TEST: git merge-file and git diff --output Tagging              "
echo "========================================================================"
echo "Git: $("$GIT_BIN" --version) ($GIT_BIN)"
echo "Test: $TEST_ROOT"
echo ""

PASSED=0
TOTAL=4

cd "$TEST_ROOT"

# ==============================================================================
# Test 1: git merge-file with IBM-1047
# ==============================================================================
echo "[Test 1/4] git merge-file with IBM-1047 encoding"

mkdir t1 && cd t1
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

echo "*.txt zos-working-tree-encoding=IBM-1047" > .gitattributes
$GIT_BIN add .gitattributes
$GIT_BIN commit -q -m "Attributes" 2>/dev/null

echo "base content" > base.txt
echo "our content" > ours.txt
echo "their content" > theirs.txt

# Run merge-file
$GIT_BIN merge-file ours.txt base.txt theirs.txt 2>/dev/null || true

TAG=$(chtag -p ours.txt 2>/dev/null | awk '{print $2}')
if [ "$TAG" = "IBM-1047" ]; then
    echo "  ✓ PASS: File tagged as IBM-1047"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ FAIL: File tagged as $TAG (expected IBM-1047)"
fi

cd ..

# ==============================================================================
# Test 2: git merge-file with UTF-8
# ==============================================================================
echo ""
echo "[Test 2/4] git merge-file with UTF-8 encoding"

mkdir t2 && cd t2
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

echo "*.txt zos-working-tree-encoding=UTF-8" > .gitattributes
$GIT_BIN add .gitattributes
$GIT_BIN commit -q -m "Attributes" 2>/dev/null

echo "base" > base.txt
echo "ours" > ours.txt
echo "theirs" > theirs.txt

$GIT_BIN merge-file ours.txt base.txt theirs.txt 2>/dev/null || true

TAG=$(chtag -p ours.txt 2>/dev/null | awk '{print $2}')
# UTF-8 could be ISO8859-1 or UTF-8 depending on system
if [ "$TAG" = "UTF-8" ] || [ "$TAG" = "ISO8859-1" ]; then
    echo "  ✓ PASS: File tagged as $TAG"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ FAIL: File tagged as $TAG"
fi

cd ..

# ==============================================================================
# Test 3: git diff --output (metadata - uses utf8_ccsid, ignores .gitattributes)
# ==============================================================================
echo ""
echo "[Test 3/4] git diff --output encoding (diff is metadata, uses utf8_ccsid)"

mkdir t3 && cd t3
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

echo "*.diff zos-working-tree-encoding=IBM-1047" > .gitattributes
$GIT_BIN add .gitattributes
$GIT_BIN commit -q -m "Attributes" 2>/dev/null

echo "version 1" > file.txt
$GIT_BIN add file.txt
$GIT_BIN commit -q -m "Version 1" 2>/dev/null

echo "version 2" > file.txt
$GIT_BIN add file.txt
$GIT_BIN commit -q -m "Version 2" 2>/dev/null

# Create diff output
$GIT_BIN diff HEAD~1 HEAD --output=output.diff

TAG=$(chtag -p output.diff 2>/dev/null | awk '{print $2}')
# Diff output is always UTF-8/ISO8859-1, regardless of .gitattributes
# Diff is metadata (not source code), so it uses utf8_ccsid
if [ "$TAG" = "UTF-8" ] || [ "$TAG" = "ISO8859-1" ]; then
    echo "  ✓ PASS: Diff file tagged as $TAG (correct: uses utf8_ccsid)"
    echo "         (Diff is metadata, ignores .gitattributes)"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ FAIL: Diff file tagged as $TAG (expected UTF-8 or ISO8859-1)"
fi

cd ..

# ==============================================================================
# Test 4: git diff --output with UTF-8
# ==============================================================================
echo ""
echo "[Test 4/4] git diff --output with UTF-8 encoding"

mkdir t4 && cd t4
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

echo "*.diff zos-working-tree-encoding=UTF-8" > .gitattributes
$GIT_BIN add .gitattributes
$GIT_BIN commit -q -m "Attributes" 2>/dev/null

echo "v1" > f.txt
$GIT_BIN add f.txt
$GIT_BIN commit -q -m "V1" 2>/dev/null

echo "v2" > f.txt
$GIT_BIN add f.txt
$GIT_BIN commit -q -m "V2" 2>/dev/null

$GIT_BIN diff HEAD~1 HEAD --output=out.diff

TAG=$(chtag -p out.diff 2>/dev/null | awk '{print $2}')
if [ "$TAG" = "UTF-8" ] || [ "$TAG" = "ISO8859-1" ]; then
    echo "  ✓ PASS: Diff file tagged as $TAG"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ FAIL: Diff file tagged as $TAG"
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
    echo "  ✓ ALL TESTS PASSED!"
    echo ""
    echo "  File tagging behavior:"
    echo "    - git merge-file: Respects .gitattributes (working tree content)"
    echo "    - git diff --output: Uses utf8_ccsid (metadata, ignores .gitattributes)"
    exit 0
else
    echo "  ✗ SOME TESTS FAILED"
    echo "  $((TOTAL - PASSED)) test(s) failed"
    exit 1
fi

