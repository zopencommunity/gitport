#!/bin/bash
#
# Test: git blame with zos-working-tree-encoding
# 
# Verifies that git blame correctly displays EBCDIC files with encoding attributes
#
# TAP format output for integration with test harness

# Check if running on z/OS
if [ "$(uname)" != "OS/390" ]; then
    echo "TAP version 13"
    echo "1..0 # SKIP Not running on z/OS"
    exit 0
fi

# Find git binary
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_BIN="${GIT_BIN:-$SCRIPT_DIR/../git/git}"
TEST_ROOT="$(pwd)/test_tmp_blame_$$"
mkdir -p "$TEST_ROOT"
trap 'cd /; rm -rf "$TEST_ROOT"' EXIT

# TAP output
echo "TAP version 13"
echo "1..3"

TEST_NUM=0
FAIL_COUNT=0

# Helper function for TAP output
tap_result() {
    TEST_NUM=$((TEST_NUM + 1))
    local status=$1
    local description=$2
    local diagnostic=$3
    
    if [ "$status" = "ok" ]; then
        echo "ok $TEST_NUM - $description"
    else
        echo "not ok $TEST_NUM - $description"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    
    if [ -n "$diagnostic" ]; then
        echo "  # $diagnostic"
    fi
}

cd "$TEST_ROOT"

# ==============================================================================
# Test 1: git blame with IBM-1047 encoding
# ==============================================================================

# Initialize repository
"$GIT_BIN" init -q 2>/dev/null
"$GIT_BIN" config user.name "Test User"
"$GIT_BIN" config user.email "test@test.com"
"$GIT_BIN" config core.ignorefiletags false

# Set up .gitattributes
echo "*.txt zos-working-tree-encoding=IBM-1047" > .gitattributes
"$GIT_BIN" add .gitattributes
"$GIT_BIN" commit -q -m "Add attributes" 2>/dev/null

# Create a file with multiple commits
echo "Line 1: First commit" > test.txt
"$GIT_BIN" add test.txt
"$GIT_BIN" commit -q -m "First commit" 2>/dev/null

echo "Line 2: Second commit" >> test.txt
"$GIT_BIN" add test.txt
"$GIT_BIN" commit -q -m "Second commit" 2>/dev/null

echo "Line 3: Third commit" >> test.txt
"$GIT_BIN" add test.txt
"$GIT_BIN" commit -q -m "Third commit" 2>/dev/null

# Run git blame and capture output
BLAME_OUTPUT=$("$GIT_BIN" blame test.txt 2>&1)
BLAME_EXIT=$?

# Check if blame command succeeded
if [ $BLAME_EXIT -eq 0 ]; then
    tap_result "ok" "git blame runs without error on IBM-1047 file"
else
    tap_result "not ok" "git blame runs without error on IBM-1047 file" "exit code: $BLAME_EXIT"
fi

# ==============================================================================
# Test 2: git blame output is readable (not garbled)
# ==============================================================================

# Check if output contains readable text (not EBCDIC garbage)
if echo "$BLAME_OUTPUT" | grep -q "First commit" && \
   echo "$BLAME_OUTPUT" | grep -q "Second commit" && \
   echo "$BLAME_OUTPUT" | grep -q "Third commit"; then
    tap_result "ok" "git blame output is readable (contains commit text)"
else
    tap_result "not ok" "git blame output is readable" "output may be garbled"
    echo "  # Actual output:"
    echo "$BLAME_OUTPUT" | head -5 | sed 's/^/  # /'
fi

# ==============================================================================
# Test 3: git blame shows line content correctly
# ==============================================================================

# Check if blame shows the actual line content
if echo "$BLAME_OUTPUT" | grep -q "Line 1: First commit" && \
   echo "$BLAME_OUTPUT" | grep -q "Line 2: Second commit" && \
   echo "$BLAME_OUTPUT" | grep -q "Line 3: Third commit"; then
    tap_result "ok" "git blame shows file content correctly (not EBCDIC bytes)"
else
    tap_result "not ok" "git blame shows file content correctly" "line content may be garbled"
    echo "  # Expected to find: 'Line 1: First commit', 'Line 2: Second commit', 'Line 3: Third commit'"
    echo "  # Actual output:"
    echo "$BLAME_OUTPUT" | sed 's/^/  # /'
fi

# Clean up
cd /
rm -rf "$TEST_ROOT"

exit $FAIL_COUNT
