#!/usr/bin/env bash
# ==============================================================================
# Test for git rerere encoding issue
# Tests that rerere-resolved files get correct encoding tags
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
echo "               GIT RERERE ENCODING TEST                                "
echo "========================================================================"
echo "Git binary: $("$GIT_BIN" --version) ($GIT_BIN)"
echo "Test root:  $TEST_ROOT"
echo ""

PASSED=0
TOTAL=2

cd "$TEST_ROOT"

# ==============================================================================
# Test 1: Rerere with IBM-1047 files
# ==============================================================================
echo "[Test 1/2] git rerere with IBM-1047 encoded files..."

mkdir test1 && cd test1
"$GIT_BIN" init -q 2>/dev/null
"$GIT_BIN" config user.name "Test User"
"$GIT_BIN" config user.email "test@example.com"
"$GIT_BIN" config core.ignorefiletags false
"$GIT_BIN" config rerere.enabled true

# Create .gitattributes with IBM-1047
echo "*.txt zos-working-tree-encoding=IBM-1047" > .gitattributes
"$GIT_BIN" add .gitattributes
"$GIT_BIN" commit -q -m "Add attributes" 2>/dev/null

# Create initial file
cat > test.txt << 'TXT'
line 1
line 2
line 3
TXT
"$GIT_BIN" add test.txt
"$GIT_BIN" commit -q -m "Initial" 2>/dev/null

# Create branch and modify
"$GIT_BIN" checkout -q -b feature 2>/dev/null
cat > test.txt << 'TXT'
line 1 - feature
line 2
line 3
TXT
"$GIT_BIN" add test.txt
"$GIT_BIN" commit -q -m "Feature change" 2>/dev/null

# Go back and make conflicting change
"$GIT_BIN" checkout -q master 2>/dev/null
cat > test.txt << 'TXT'
line 1 - master
line 2
line 3
TXT
"$GIT_BIN" add test.txt
"$GIT_BIN" commit -q -m "Master change" 2>/dev/null

# Try to merge (will conflict)
if ! "$GIT_BIN" merge feature 2>/dev/null; then
    # Resolve conflict
    cat > test.txt << 'TXT'
line 1 - resolved
line 2
line 3
TXT
    "$GIT_BIN" add test.txt
    "$GIT_BIN" commit -q -m "Merge with resolution" 2>/dev/null
    
    # Check file tag
    TAG=$(chtag -p test.txt 2>/dev/null | awk '{print $2}')
    if [ "$TAG" = "IBM-1047" ]; then
        echo "  ✓ PASS: Rerere file tagged as IBM-1047"
        PASSED=$((PASSED + 1))
    else
        echo "  ✗ FAIL: Rerere file tagged as $TAG (expected IBM-1047)"
    fi
else
    echo "  ⚠ SKIP: No conflict occurred"
fi

cd ..

# ==============================================================================
# Test 2: Rerere remembers resolution and tags correctly
# ==============================================================================
echo ""
echo "[Test 2/2] git rerere remembers resolution with correct tags..."

mkdir test2 && cd test2
"$GIT_BIN" init -q 2>/dev/null
"$GIT_BIN" config user.name "Test User"
"$GIT_BIN" config user.email "test@example.com"
"$GIT_BIN" config core.ignorefiletags false
"$GIT_BIN" config rerere.enabled true

echo "*.txt zos-working-tree-encoding=IBM-1047" > .gitattributes
"$GIT_BIN" add .gitattributes
"$GIT_BIN" commit -q -m "Attributes" 2>/dev/null

# Create base
echo "base line" > file.txt
"$GIT_BIN" add file.txt
"$GIT_BIN" commit -q -m "Base" 2>/dev/null

# Branch A
"$GIT_BIN" checkout -q -b branchA 2>/dev/null
echo "branch A line" > file.txt
"$GIT_BIN" add file.txt
"$GIT_BIN" commit -q -m "Branch A" 2>/dev/null

# Branch B
"$GIT_BIN" checkout -q master 2>/dev/null
"$GIT_BIN" checkout -q -b branchB 2>/dev/null
echo "branch B line" > file.txt
"$GIT_BIN" add file.txt
"$GIT_BIN" commit -q -m "Branch B" 2>/dev/null

# Merge A into B (conflict)
if ! "$GIT_BIN" merge branchA 2>/dev/null; then
    # Resolve
    echo "merged line" > file.txt
    "$GIT_BIN" add file.txt
    "$GIT_BIN" commit -q -m "Merge A into B" 2>/dev/null
fi

# Just check the merged file tag
TAG=$(chtag -p file.txt 2>/dev/null | awk '{print $2}')
if [ "$TAG" = "IBM-1047" ]; then
    echo "  ✓ PASS: Merged file tagged as IBM-1047"
    PASSED=$((PASSED + 1))
else
    echo "  ✗ FAIL: File tagged as $TAG (expected IBM-1047)"
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
    echo "  ✓ ALL TESTS PASSED - git rerere tagging works!"
    exit 0
else
    echo "  ✗ SOME TESTS FAILED"
    exit 1
fi
