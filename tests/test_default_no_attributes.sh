#!/bin/bash
#
# Test: Default behavior with no .gitattributes
# 
# This test verifies correct default file tagging when:
# - No .gitattributes file exists
# - Empty .gitattributes
# - No patterns match the file
#
# TAP format output

# Check if running on z/OS
if [ "$(uname)" != "OS/390" ]; then
    echo "1..0 # SKIP Not running on z/OS"
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_BIN="${GIT_BIN:-$SCRIPT_DIR/../git/git}"
TEST_ROOT="$(pwd)/test_tmp_$$"
mkdir -p "$TEST_ROOT"
trap 'rm -rf "$TEST_ROOT"' EXIT

# Get the expected default tag based on GIT_UTF8_CCSID
if [ "$GIT_UTF8_CCSID" = "819" ]; then
    EXPECTED_TAG="ISO8859-1"
elif [ "$GIT_UTF8_CCSID" = "1208" ]; then
    EXPECTED_TAG="UTF-8"
else
    # Default to ISO8859-1 if not set
    EXPECTED_TAG="ISO8859-1"
fi

echo "TAP version 13"
echo "1..4"

TEST_NUM=0
FAIL_COUNT=0

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

# Test 1: No .gitattributes file at all
# ======================================
cd "$TEST_ROOT"
mkdir test1 && cd test1

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

# Don't create .gitattributes
echo "Hello World" > file.txt

$GIT_BIN add file.txt 2>/dev/null
$GIT_BIN commit -m "test" -q 2>/dev/null

rm file.txt
$GIT_BIN checkout HEAD file.txt 2>/dev/null

TAG1=$(chtag -p file.txt 2>/dev/null | awk '{print $2}')

if [ "$TAG1" = "$EXPECTED_TAG" ]; then
    tap_result "ok" "No .gitattributes: default tag is $EXPECTED_TAG"
else
    tap_result "not ok" "No .gitattributes: default tag is $EXPECTED_TAG" "got: $TAG1, expected: $EXPECTED_TAG"
fi

cd "$TEST_ROOT"

# Test 2: Empty .gitattributes
# =============================
mkdir test2 && cd test2

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

# Create empty .gitattributes
touch .gitattributes
echo "Hello World" > file.txt

$GIT_BIN add .gitattributes file.txt 2>/dev/null
$GIT_BIN commit -m "test" -q 2>/dev/null

rm file.txt
$GIT_BIN checkout HEAD file.txt 2>/dev/null

TAG2=$(chtag -p file.txt 2>/dev/null | awk '{print $2}')

if [ "$TAG2" = "$EXPECTED_TAG" ]; then
    tap_result "ok" "Empty .gitattributes: default tag is $EXPECTED_TAG"
else
    tap_result "not ok" "Empty .gitattributes: default tag is $EXPECTED_TAG" "got: $TAG2, expected: $EXPECTED_TAG"
fi

cd "$TEST_ROOT"

# Test 3: Non-matching patterns
# ==============================
mkdir test3 && cd test3

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

cat << 'EOF' > .gitattributes
*.java text zos-working-tree-encoding=IBM-1047
*.cpp text zos-working-tree-encoding=UTF-8
EOF

# Create a file that doesn't match any pattern
echo "Hello World" > readme.md

$GIT_BIN add .gitattributes readme.md 2>/dev/null
$GIT_BIN commit -m "test" -q 2>/dev/null

rm readme.md
$GIT_BIN checkout HEAD readme.md 2>/dev/null

TAG3=$(chtag -p readme.md 2>/dev/null | awk '{print $2}')

if [ "$TAG3" = "$EXPECTED_TAG" ]; then
    tap_result "ok" "Non-matching patterns: default tag is $EXPECTED_TAG"
else
    tap_result "not ok" "Non-matching patterns: default tag is $EXPECTED_TAG" "got: $TAG3, expected: $EXPECTED_TAG"
fi

cd "$TEST_ROOT"

# Test 4: Comments and blank lines in .gitattributes
# ===================================================
mkdir test4 && cd test4

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

cat << 'EOF' > .gitattributes
# This is a comment
*.java text zos-working-tree-encoding=IBM-1047

# Another comment
*.cpp text zos-working-tree-encoding=UTF-8

EOF

# File doesn't match
echo "Hello World" > notes.txt

$GIT_BIN add .gitattributes notes.txt 2>/dev/null
$GIT_BIN commit -m "test" -q 2>/dev/null

rm notes.txt
$GIT_BIN checkout HEAD notes.txt 2>/dev/null

TAG4=$(chtag -p notes.txt 2>/dev/null | awk '{print $2}')

if [ "$TAG4" = "$EXPECTED_TAG" ]; then
    tap_result "ok" "Comments in .gitattributes: default tag is $EXPECTED_TAG"
else
    tap_result "not ok" "Comments in .gitattributes: default tag is $EXPECTED_TAG" "got: $TAG4, expected: $EXPECTED_TAG"
fi

# Clean up
cd /
rm -rf "$TEST_ROOT"

exit $FAIL_COUNT
