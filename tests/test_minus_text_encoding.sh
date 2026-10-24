#!/bin/bash
#
# Test: -text + zos-working-tree-encoding attribute bug
# 
# This test verifies that git correctly tags files with zos-working-tree-encoding
# even when -text attribute is set (which should only disable EOL conversion,
# not treat the file as binary).
#
# TAP format output for integration with zopen_check_results

# Check if running on z/OS
if [ "$(uname)" != "OS/390" ]; then
    echo "1..0 # SKIP Not running on z/OS"
    exit 0
fi

# Find git binary relative to test location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_BIN="${GIT_BIN:-$SCRIPT_DIR/../git/git}"
TEST_ROOT="$(pwd)/test_tmp_$$"
mkdir -p "$TEST_ROOT"
trap 'rm -rf "$TEST_ROOT"' EXIT

# TAP output
echo "TAP version 13"
echo "1..4"

TEST_NUM=0

# Helper function for TAP output
tap_result() {
    TEST_NUM=$((TEST_NUM + 1))
    local status=$1
    local description=$2
    local directive=$3
    
    if [ "$status" = "ok" ]; then
        echo "ok $TEST_NUM - $description"
    else
        echo "not ok $TEST_NUM - $description"
    fi
    
    if [ -n "$directive" ]; then
        echo "  # $directive"
    fi
}

# Clean up from helper functions
rm -rf "$TEST_ROOT"
mkdir -p "$TEST_ROOT"  # Recreate before tests

# Test 1: Baseline with 'text' attribute (should work)
# =====================================================
cd "$TEST_ROOT"
mkdir test1 && cd test1

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

cat << 'EOF' > .gitattributes
*.txt text zos-working-tree-encoding=ibm-1047
EOF

touch test.txt
chtag -tc 1047 test.txt
echo "Line 1" > test.txt

$GIT_BIN add .gitattributes test.txt 2>/dev/null
$GIT_BIN commit -m "test" -q 2>/dev/null

rm test.txt
$GIT_BIN checkout HEAD test.txt 2>/dev/null

TAG1=$(chtag -p test.txt 2>/dev/null | awk '{print $2}')

if [ "$TAG1" = "IBM-1047" ]; then
    tap_result "ok" "text attribute with zos-working-tree-encoding tags as IBM-1047"
else
    tap_result "not ok" "text attribute with zos-working-tree-encoding tags as IBM-1047" "got: $TAG1"
fi

cd "$TEST_ROOT"

# Test 2: -text attribute (the bug)
# ==================================
mkdir test2 && cd test2

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

cat << 'EOF' > .gitattributes
*.txt -text zos-working-tree-encoding=ibm-1047
EOF

touch test.txt
chtag -tc 1047 test.txt
echo "Line 1" > test.txt

$GIT_BIN add .gitattributes test.txt 2>/dev/null
$GIT_BIN commit -m "test" -q 2>/dev/null

rm test.txt
$GIT_BIN checkout HEAD test.txt 2>/dev/null

TAG2=$(chtag -p test.txt 2>/dev/null | awk '{print $1, $2}')

if echo "$TAG2" | grep -q "t IBM-1047"; then
    tap_result "ok" "-text attribute with zos-working-tree-encoding tags as IBM-1047"
else
    tap_result "not ok" "-text attribute with zos-working-tree-encoding tags as IBM-1047" "got: $TAG2, expected: t IBM-1047"
fi

cd "$TEST_ROOT"

# Test 3: Mixed-codepage file with -text
# =======================================
mkdir test3 && cd test3

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

cat << 'EOF' > .gitattributes
*.dat -text zos-working-tree-encoding=ibm-1047
EOF

touch mixed.dat
chtag -tc 1047 mixed.dat
echo "EBCDIC line 1" > mixed.dat
printf "\x42\xC1\x43" >> mixed.dat
echo "" >> mixed.dat

$GIT_BIN add .gitattributes mixed.dat 2>/dev/null
$GIT_BIN commit -m "mixed" -q 2>/dev/null

rm mixed.dat
$GIT_BIN checkout HEAD mixed.dat 2>/dev/null

TAG3=$(chtag -p mixed.dat 2>/dev/null | awk '{print $1, $2}')

if echo "$TAG3" | grep -q "t IBM-1047"; then
    tap_result "ok" "mixed-codepage file with -text tags as IBM-1047"
else
    tap_result "not ok" "mixed-codepage file with -text tags as IBM-1047" "got: $TAG3, expected: t IBM-1047"
fi

cd "$TEST_ROOT"

# Test 4: nickrayjones' scenario
# ===============================
mkdir test4 && cd test4

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

cat << 'EOF' > .gitattributes
* -text git-encoding=utf-8 zos-working-tree-encoding=ibm-1047 working-tree-encoding=utf-8
EOF

touch file.txt
chtag -tc 1047 file.txt
echo "Test content" > file.txt

$GIT_BIN add .gitattributes file.txt 2>/dev/null
$GIT_BIN commit -m "test" -q 2>/dev/null

rm file.txt
$GIT_BIN checkout HEAD file.txt 2>/dev/null

TAG4=$(chtag -p file.txt 2>/dev/null | awk '{print $1, $2}')

if echo "$TAG4" | grep -q "t IBM-1047"; then
    tap_result "ok" "nickrayjones scenario (-text with multiple encoding attrs) tags as IBM-1047"
else
    tap_result "not ok" "nickrayjones scenario (-text with multiple encoding attrs) tags as IBM-1047" "got: $TAG4, expected: t IBM-1047"
fi

# Clean up
cd /
rm -rf "$TEST_ROOT"

# Exit with failure if any tests failed
if [ $TEST_NUM -eq 4 ]; then
    # Count actual passes by checking tags
    ACTUAL_PASSES=0
    [ "$TAG1" = "IBM-1047" ] && ACTUAL_PASSES=$((ACTUAL_PASSES + 1))
    echo "$TAG2" | grep -q "t IBM-1047" && ACTUAL_PASSES=$((ACTUAL_PASSES + 1))
    echo "$TAG3" | grep -q "t IBM-1047" && ACTUAL_PASSES=$((ACTUAL_PASSES + 1))
    echo "$TAG4" | grep -q "t IBM-1047" && ACTUAL_PASSES=$((ACTUAL_PASSES + 1))
    
    if [ $ACTUAL_PASSES -eq 4 ]; then
        exit 0  # All tests passed
    else
        exit 1  # Some tests failed (bug still exists)
    fi
fi

exit 1
