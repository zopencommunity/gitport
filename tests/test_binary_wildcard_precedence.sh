#!/bin/bash
#
# Test: Binary files with wildcard encoding precedence
# 
# This test verifies that explicit 'binary' attribute overrides wildcard
# encoding settings. Common in enterprise repos:
#   * text working-tree-encoding=UTF-8
#   *.png binary
# 
# The .png file should be tagged as binary, NOT UTF-8.
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

# Source shared helper functions
source "$SCRIPT_DIR/test_helpers.sh"

# TAP output
echo "TAP version 13"
echo "1..8"

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

# Test: Wildcard encoding + multiple binary types
# ===============================================
cd "$TEST_ROOT"
mkdir test1 && cd test1

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

# Create .gitattributes with wildcard + binary overrides
cat << 'EOF' > .gitattributes
* text working-tree-encoding=UTF-8
.gitattributes working-tree-encoding=ISO8859-1
*.png binary -working-tree-encoding
*.jpg binary -working-tree-encoding
*.pdf binary -working-tree-encoding
*.jar binary -working-tree-encoding
*.exe binary -working-tree-encoding
EOF

# Create fake binary files (just need them to exist)
echo -e "\x89PNG\x0D\x0A\x1A\x0A" > image.png
echo -e "\xFF\xD8\xFF\xE0" > photo.jpg
echo -e "%PDF-1.4" > document.pdf
echo -e "PK\x03\x04" > library.jar
echo -e "MZ" > program.exe

# Also create a text file to verify wildcard encoding works
echo "Text file" > readme.txt

$GIT_BIN add .gitattributes *.png *.jpg *.pdf *.jar *.exe readme.txt 2>/dev/null
$GIT_BIN commit -m "test" -q 2>/dev/null

# Remove files and checkout to test tagging
rm -f image.png photo.jpg document.pdf library.jar program.exe readme.txt
$GIT_BIN checkout HEAD . 2>/dev/null

# Check tags
TAG_PNG=$(chtag -p image.png 2>/dev/null | awk '{print $1, $2}')
TAG_JPG=$(chtag -p photo.jpg 2>/dev/null | awk '{print $1, $2}')
TAG_PDF=$(chtag -p document.pdf 2>/dev/null | awk '{print $1, $2}')
TAG_JAR=$(chtag -p library.jar 2>/dev/null | awk '{print $1, $2}')
TAG_EXE=$(chtag -p program.exe 2>/dev/null | awk '{print $1, $2}')
TAG_TXT=$(chtag -p readme.txt 2>/dev/null | awk '{print $2}')

# Get expected UTF-8 tag
EXPECTED_UTF8=$(get_expected_utf8_tag)

# Test results
if echo "$TAG_PNG" | grep -q "b binary"; then
    tap_result "ok" "PNG file tagged as binary (not UTF-8)"
else
    tap_result "not ok" "PNG file tagged as binary (not UTF-8)" "got: $TAG_PNG, expected: b binary"
fi

if echo "$TAG_JPG" | grep -q "b binary"; then
    tap_result "ok" "JPG file tagged as binary (not UTF-8)"
else
    tap_result "not ok" "JPG file tagged as binary (not UTF-8)" "got: $TAG_JPG, expected: b binary"
fi

if echo "$TAG_PDF" | grep -q "b binary"; then
    tap_result "ok" "PDF file tagged as binary (not UTF-8)"
else
    tap_result "not ok" "PDF file tagged as binary (not UTF-8)" "got: $TAG_PDF, expected: b binary"
fi

if echo "$TAG_JAR" | grep -q "b binary"; then
    tap_result "ok" "JAR file tagged as binary (not UTF-8)"
else
    tap_result "not ok" "JAR file tagged as binary (not UTF-8)" "got: $TAG_JAR, expected: b binary"
fi

if echo "$TAG_EXE" | grep -q "b binary"; then
    tap_result "ok" "EXE file tagged as binary (not UTF-8)"
else
    tap_result "not ok" "EXE file tagged as binary (not UTF-8)" "got: $TAG_EXE, expected: b binary"
fi

if is_expected_utf8_tag "$TAG_TXT"; then
    tap_result "ok" "Text file tagged as $EXPECTED_UTF8 (wildcard works)"
else
    tap_result "not ok" "Text file tagged as $EXPECTED_UTF8 (wildcard works)" "got: $TAG_TXT, expected: $EXPECTED_UTF8"
fi

cd "$TEST_ROOT"

# Test: Git merge with binary files
# ==================================
mkdir test2 && cd test2

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

cat << 'EOF' > .gitattributes
* text working-tree-encoding=ISO8859-1
.gitattributes working-tree-encoding=ISO8859-1
*.dll binary -working-tree-encoding
EOF

echo -e "MZ\x90\x00" > library.dll
chtag -b library.dll 2>/dev/null
$GIT_BIN add .gitattributes library.dll 2>/dev/null
$GIT_BIN commit -m "master" -q 2>/dev/null

# Create branch
$GIT_BIN checkout -b feature -q 2>/dev/null
echo -e "MZ\x90\x01" > library.dll
chtag -b library.dll 2>/dev/null
$GIT_BIN add library.dll 2>/dev/null
$GIT_BIN commit -m "feature" -q 2>/dev/null

# Merge back
$GIT_BIN checkout master -q 2>/dev/null
$GIT_BIN merge feature -q 2>/dev/null || true

TAG_DLL=$(chtag -p library.dll 2>/dev/null | awk '{print $1, $2}')

if echo "$TAG_DLL" | grep -q "b binary"; then
    tap_result "ok" "Binary file stays binary after merge"
else
    tap_result "not ok" "Binary file stays binary after merge" "got: $TAG_DLL, expected: b binary"
fi

cd "$TEST_ROOT"

# Test: Git clone with binary files
# ==================================
mkdir test3 && cd test3

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

cat << 'EOF' > .gitattributes
* text working-tree-encoding=IBM-1047
.gitattributes working-tree-encoding=ISO8859-1
*.so binary -working-tree-encoding
EOF

echo -e "\x7FELF" > libtest.so
chtag -b libtest.so 2>/dev/null
$GIT_BIN add .gitattributes libtest.so 2>/dev/null
$GIT_BIN commit -m "test" -q 2>/dev/null

# Clone to new directory
cd "$TEST_ROOT"
$GIT_BIN clone -q test3 test3_clone 2>/dev/null

cd test3_clone
TAG_SO=$(chtag -p libtest.so 2>/dev/null | awk '{print $1, $2}')

if echo "$TAG_SO" | grep -q "b binary"; then
    tap_result "ok" "Binary file tagged correctly after clone"
else
    tap_result "not ok" "Binary file tagged correctly after clone" "got: $TAG_SO, expected: b binary"
fi

# Clean up
cd /
rm -rf "$TEST_ROOT"

exit $FAIL_COUNT
