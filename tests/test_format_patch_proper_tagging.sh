#!/bin/bash
#
# Test: git format-patch with proper vs improper file tagging
# 
# This test demonstrates that git format-patch works correctly when files
# are properly tagged, and produces garbled output when files are improperly tagged.
#
# This is a USER WORKFLOW issue, not a git bug.
#
# TAP format output for integration with zopen_check_results

# Check if running on z/OS
if [ "$(uname)" != "OS/390" ]; then
    echo "1..0 # SKIP Test only runs on z/OS"
    exit 0
fi

# Find git binary relative to test location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_BIN="${GIT_BIN:-$SCRIPT_DIR/../git/git}"
TEST_ROOT="$(pwd)/test_tmp_$$"

# TAP output
echo "TAP version 13"
echo "1..2"

TEST_NUM=0
FAILED=0

# Clean up on exit
cleanup() {
    cd /
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$TEST_ROOT"
cd "$TEST_ROOT"

# ==============================================================================
# Test 1: Improper tagging (files created without chtag) - EXPECTED TO FAIL
# ==============================================================================
TEST_NUM=$((TEST_NUM + 1))

mkdir test_wrong
cd test_wrong

$GIT_BIN init >/dev/null 2>&1
$GIT_BIN config user.email "test@example.com"
$GIT_BIN config user.name "Test User"
echo "* zos-working-tree-encoding=ibm-1047" > .gitattributes
$GIT_BIN add .gitattributes >/dev/null 2>&1
$GIT_BIN commit -m "Add gitattributes" >/dev/null 2>&1

# Create files WITHOUT proper tagging (wrong workflow)
echo "Initial content" > testfile.txt
$GIT_BIN add testfile.txt >/dev/null 2>&1
$GIT_BIN commit -m "Initial commit" >/dev/null 2>&1

echo "Modified content" > testfile.txt
$GIT_BIN add testfile.txt >/dev/null 2>&1
$GIT_BIN commit -m "Modify testfile" >/dev/null 2>&1
$GIT_BIN format-patch -1 HEAD -o "$TEST_ROOT/test_wrong" >/dev/null 2>&1

$GIT_BIN reset --hard HEAD~1 >/dev/null 2>&1
echo "Different content" > testfile.txt
$GIT_BIN add testfile.txt >/dev/null 2>&1
$GIT_BIN commit -m "Different modification" >/dev/null 2>&1

$GIT_BIN apply --3way "$TEST_ROOT/test_wrong/0001-Modify-testfile.patch" >/dev/null 2>&1

# Check if output contains garbled text (non-ASCII in theirs section)
RESULT=$(cat testfile.txt)
if echo "$RESULT" | grep -q "Modified content"; then
    echo "not ok $TEST_NUM - improper tagging produces garbled output (expected to fail)"
    echo "  # Unexpected: Got readable output with improper tagging"
    FAILED=1
else
    echo "ok $TEST_NUM - improper tagging produces garbled output (expected behavior)"
fi

cd "$TEST_ROOT"

# ==============================================================================
# Test 2: Proper tagging (files tagged before writing content) - SHOULD PASS
# ==============================================================================
TEST_NUM=$((TEST_NUM + 1))

mkdir test_right
cd test_right

$GIT_BIN init >/dev/null 2>&1
$GIT_BIN config user.email "test@example.com"
$GIT_BIN config user.name "Test User"
echo "* zos-working-tree-encoding=ISO8859-1" > .gitattributes
$GIT_BIN add .gitattributes >/dev/null 2>&1
$GIT_BIN commit -m "Add gitattributes" >/dev/null 2>&1

# Create files WITH proper tagging (correct workflow)
# Use ISO8859-1 which is compatible with ASCII on z/OS
echo "Initial content" > testfile.txt
chtag -tc ISO8859-1 testfile.txt
$GIT_BIN add testfile.txt >/dev/null 2>&1
$GIT_BIN commit -m "Initial commit" >/dev/null 2>&1

echo "Modified content" > testfile.txt
chtag -tc ISO8859-1 testfile.txt
$GIT_BIN add testfile.txt >/dev/null 2>&1
$GIT_BIN commit -m "Modify testfile" >/dev/null 2>&1
$GIT_BIN format-patch -1 HEAD -o "$TEST_ROOT/test_right" >/dev/null 2>&1

$GIT_BIN reset --hard HEAD~1 >/dev/null 2>&1
echo "Different content" > testfile.txt
chtag -tc ISO8859-1 testfile.txt
$GIT_BIN add testfile.txt >/dev/null 2>&1
$GIT_BIN commit -m "Different modification" >/dev/null 2>&1

$GIT_BIN apply --3way "$TEST_ROOT/test_right/0001-Modify-testfile.patch" >/dev/null 2>&1

# Check if output contains readable text
# With ISO8859-1, the file should be readable as-is
RESULT=$(cat testfile.txt)
if echo "$RESULT" | grep -q "Modified content"; then
    echo "ok $TEST_NUM - proper tagging produces readable output"
else
    echo "not ok $TEST_NUM - proper tagging produces readable output"
    echo "  # Expected 'Modified content' in conflict markers"
    echo "  # Got: $RESULT"
    FAILED=1
fi

# Clean up
cd /
rm -rf "$TEST_ROOT"

# Exit with failure if any test failed
exit $FAILED
