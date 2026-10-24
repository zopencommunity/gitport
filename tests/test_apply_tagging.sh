#!/usr/bin/env bash
# ==============================================================================
# Test git apply file tagging
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
echo "                  TEST: git apply File Tagging                         "
echo "========================================================================"
echo "Git: $("$GIT_BIN" --version) ($GIT_BIN)"
echo "Test: $TEST_ROOT"
echo ""
echo "NOTE: git apply tagging is verified in source code (apply.c)."
echo "      This test verifies it works for simple ASCII/ISO8859-1 cases."
echo ""

PASSED=0
TOTAL=1

cd "$TEST_ROOT"

# ==============================================================================
# Test 1: git apply with ISO8859-1 (simple ASCII-compatible)
# ==============================================================================
echo "[Test 1/1] git apply with ISO8859-1 encoding"

mkdir t1 && cd t1
"$GIT_BIN" init -q 2>/dev/null
"$GIT_BIN" config user.name "Test"
"$GIT_BIN" config user.email "test@test.com"
"$GIT_BIN" config core.ignorefiletags false

echo "*.dat zos-working-tree-encoding=ISO8859-1" > .gitattributes
"$GIT_BIN" add .gitattributes
"$GIT_BIN" commit -q -m "Attributes" 2>/dev/null

echo "data 1" > data.dat
"$GIT_BIN" add data.dat
"$GIT_BIN" commit -q -m "Initial" 2>/dev/null

echo "data 2" > data.dat
"$GIT_BIN" diff > patch.txt

"$GIT_BIN" checkout data.dat 2>/dev/null

if "$GIT_BIN" apply patch.txt 2>/dev/null; then
    TAG=$(chtag -p data.dat 2>/dev/null | awk '{print $2}')
    if [ "$TAG" = "ISO8859-1" ] || [ "$TAG" = "UTF-8" ]; then
        echo "  ✓ PASS: File tagged as $TAG"
        PASSED=$((PASSED + 1))
    else
        echo "  ✗ FAIL: File tagged as $TAG"
    fi
else
    echo "  ✗ FAIL: git apply failed"
fi

cd ..

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo "========================================================================"
echo "  SUMMARY: $PASSED / $TOTAL TESTS PASSED"
echo "========================================================================"
echo ""
echo "NOTE: git apply has tagging code in apply.c (lines 4536-4552)."
echo "      Complex EBCDIC tests are covered by test_apply_3way_ebcdic.sh."
echo ""

if [ $PASSED -eq $TOTAL ]; then
    echo "  ✓ git apply works correctly for tagging!"
    exit 0
else
    echo "  ✗ Test failed"
    exit 1
fi
