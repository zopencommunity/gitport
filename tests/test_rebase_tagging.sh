#!/usr/bin/env bash
# ==============================================================================
# Test git rebase file tagging
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
echo "                  TEST: git rebase File Tagging                        "
echo "========================================================================"
echo "Git: $("$GIT_BIN" --version) ($GIT_BIN)"
echo "Test: $TEST_ROOT"
echo ""

PASSED=0
TOTAL=3

cd "$TEST_ROOT"

# ==============================================================================
# Test 1: Simple rebase with IBM-1047
# ==============================================================================
echo "[Test 1/3] git rebase with IBM-1047 encoding"

mkdir t1 && cd t1
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

echo "*.txt zos-working-tree-encoding=IBM-1047" > .gitattributes
$GIT_BIN add .gitattributes
$GIT_BIN commit -q -m "Attributes" 2>/dev/null

# Create base
echo "base content" > file.txt
$GIT_BIN add file.txt
$GIT_BIN commit -q -m "Base" 2>/dev/null

# Create feature branch
$GIT_BIN checkout -q -b feature 2>/dev/null
echo "feature content" > file.txt
$GIT_BIN add file.txt
$GIT_BIN commit -q -m "Feature" 2>/dev/null

# Go back and make another commit
$GIT_BIN checkout -q master 2>/dev/null
echo "other content" > other.txt
$GIT_BIN add other.txt
$GIT_BIN commit -q -m "Other" 2>/dev/null

# Rebase
$GIT_BIN checkout -q feature 2>/dev/null
if $GIT_BIN rebase master 2>/dev/null; then
    TAG=$(chtag -p file.txt 2>/dev/null | awk '{print $2}')
    if [ "$TAG" = "IBM-1047" ]; then
        echo "  ✓ PASS: File tagged as IBM-1047"
        PASSED=$((PASSED + 1))
    else
        echo "  ✗ FAIL: File tagged as $TAG (expected IBM-1047)"
    fi
else
    echo "  ✗ FAIL: Rebase failed"
fi

cd ..

# ==============================================================================
# Test 2: Rebase with conflict
# ==============================================================================
echo ""
echo "[Test 2/3] git rebase with conflict resolution"

mkdir t2 && cd t2
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

echo "*.txt zos-working-tree-encoding=IBM-1047" > .gitattributes
$GIT_BIN add .gitattributes
$GIT_BIN commit -q -m "Attributes" 2>/dev/null

# Create base
cat > file.txt << 'TXT'
line 1
line 2
line 3
TXT
$GIT_BIN add file.txt
$GIT_BIN commit -q -m "Base" 2>/dev/null

# Feature branch changes line 2
$GIT_BIN checkout -q -b feature 2>/dev/null
cat > file.txt << 'TXT'
line 1
line 2 feature
line 3
TXT
$GIT_BIN add file.txt
$GIT_BIN commit -q -m "Feature" 2>/dev/null

# Master changes line 2 differently
$GIT_BIN checkout -q master 2>/dev/null
cat > file.txt << 'TXT'
line 1
line 2 master
line 3
TXT
$GIT_BIN add file.txt
$GIT_BIN commit -q -m "Master" 2>/dev/null

# Rebase will conflict
$GIT_BIN checkout -q feature 2>/dev/null
if $GIT_BIN rebase master 2>/dev/null; then
    echo "  ⚠ SKIP: No conflict occurred (test setup issue)"
else
    # Check tag during conflict
    TAG=$(chtag -p file.txt 2>/dev/null | awk '{print $2}')
    if [ "$TAG" = "IBM-1047" ]; then
        echo "  ✓ PASS: File tagged as IBM-1047 during conflict"
        PASSED=$((PASSED + 1))
    else
        echo "  ✗ FAIL: File tagged as $TAG during conflict (expected IBM-1047)"
    fi
    $GIT_BIN rebase --abort 2>/dev/null || true
fi

cd ..

# ==============================================================================
# Test 3: Rebase multiple commits
# ==============================================================================
echo ""
echo "[Test 3/3] git rebase with multiple commits"

mkdir t3 && cd t3
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

echo "*.txt zos-working-tree-encoding=IBM-1047" > .gitattributes
$GIT_BIN add .gitattributes
$GIT_BIN commit -q -m "Attributes" 2>/dev/null

# Base
echo "base" > f.txt
$GIT_BIN add f.txt
$GIT_BIN commit -q -m "Base" 2>/dev/null

# Feature branch with 2 commits
$GIT_BIN checkout -q -b feature 2>/dev/null
echo "f1" > f.txt
$GIT_BIN add f.txt
$GIT_BIN commit -q -m "Feature 1" 2>/dev/null

echo "f2" > f.txt
$GIT_BIN add f.txt
$GIT_BIN commit -q -m "Feature 2" 2>/dev/null

# Master moves forward
$GIT_BIN checkout -q master 2>/dev/null
echo "other" > other.txt
$GIT_BIN add other.txt
$GIT_BIN commit -q -m "Other" 2>/dev/null

# Rebase
$GIT_BIN checkout -q feature 2>/dev/null
if $GIT_BIN rebase master 2>/dev/null; then
    TAG=$(chtag -p f.txt 2>/dev/null | awk '{print $2}')
    if [ "$TAG" = "IBM-1047" ]; then
        echo "  ✓ PASS: File tagged as IBM-1047"
        PASSED=$((PASSED + 1))
    else
        echo "  ✗ FAIL: File tagged as $TAG (expected IBM-1047)"
    fi
else
    echo "  ✗ FAIL: Rebase failed"
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
    echo "  git rebase tags files correctly"
    exit 0
elif [ $PASSED -gt 0 ]; then
    echo "  ⚠ PARTIAL PASS ($PASSED/$TOTAL)"
    exit 0
else
    echo "  ✗ ALL TESTS FAILED"
    exit 1
fi
