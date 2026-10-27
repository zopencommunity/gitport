#!/bin/bash
#
# Test: git stash push <file> with zos-working-tree-encoding
# 
# Issue: When running 'git stash push <file>' with a specific file,
# the file is restored with wrong encoding tag (ISO8859-1 instead of IBM-1047)
#
# Expected: File should retain its zos-working-tree-encoding tag
# Actual: File gets default ISO8859-1 tag
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

# Clean up from helper functions
rm -rf "$TEST_ROOT"
mkdir -p "$TEST_ROOT"  # Recreate before tests

# Test 1: git stash push <file> with IBM-1047 encoding
# =====================================================
cd "$TEST_ROOT"
mkdir test1 && cd test1

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

# Create .gitattributes like the issue describes
mkdir -p cobfe/zosGen/src
cat > .gitattributes << 'EOF'
cobfe/zosGen/src/* zos-working-tree-encoding=ibm-1047
EOF

# Create EBCDIC file
cat > temp.txt << 'EOF'
       IDENTIFICATION DIVISION.
       PROGRAM-ID. TESTPROG.
       DATA DIVISION.
EOF

iconv -f ISO8859-1 -t IBM-1047 < temp.txt > cobfe/zosGen/src/igyvcntl.plx
chtag -tc 1047 cobfe/zosGen/src/igyvcntl.plx
rm temp.txt

$GIT_BIN add .gitattributes cobfe/zosGen/src/igyvcntl.plx 2>/dev/null
$GIT_BIN commit -m "Initial commit" -q 2>/dev/null

# Modify the file
echo "       01  WS-VAR PIC X(10)." | iconv -f ISO8859-1 -t IBM-1047 >> cobfe/zosGen/src/igyvcntl.plx
chtag -tc 1047 cobfe/zosGen/src/igyvcntl.plx

# Stash the specific file
$GIT_BIN stash push cobfe/zosGen/src/igyvcntl.plx 2>/dev/null

# Check the tag
TAG1=$(chtag -p cobfe/zosGen/src/igyvcntl.plx 2>/dev/null | awk '{print $2}')

if [ "$TAG1" = "IBM-1047" ]; then
    tap_result "ok" "git stash push <file> preserves IBM-1047 tag"
else
    tap_result "not ok" "git stash push <file> preserves IBM-1047 tag" "got: $TAG1, expected: IBM-1047"
fi

cd "$TEST_ROOT"

# Test 2: git stash pop restores correct tag
# ===========================================
mkdir test2 && cd test2

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

mkdir -p src
echo "src/* zos-working-tree-encoding=ibm-1047" > .gitattributes

echo "Test content" | iconv -f ISO8859-1 -t IBM-1047 > src/file.txt
chtag -tc 1047 src/file.txt

$GIT_BIN add .gitattributes src/file.txt 2>/dev/null
$GIT_BIN commit -m "Initial" -q 2>/dev/null

echo "Modified" | iconv -f ISO8859-1 -t IBM-1047 >> src/file.txt
chtag -tc 1047 src/file.txt

$GIT_BIN stash push src/file.txt 2>/dev/null
$GIT_BIN stash pop 2>/dev/null

TAG2=$(chtag -p src/file.txt 2>/dev/null | awk '{print $2}')

if [ "$TAG2" = "IBM-1047" ]; then
    tap_result "ok" "git stash pop restores IBM-1047 tag correctly"
else
    tap_result "not ok" "git stash pop restores IBM-1047 tag correctly" "got: $TAG2, expected: IBM-1047"
fi

cd "$TEST_ROOT"

# Test 3: git stash (without file) works correctly (baseline)
# ============================================================
mkdir test3 && cd test3

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

mkdir -p data
echo "data/* zos-working-tree-encoding=ibm-1047" > .gitattributes

echo "Data file" | iconv -f ISO8859-1 -t IBM-1047 > data/data.txt
chtag -tc 1047 data/data.txt

$GIT_BIN add .gitattributes data/data.txt 2>/dev/null
$GIT_BIN commit -m "Initial" -q 2>/dev/null

echo "Modified data" | iconv -f ISO8859-1 -t IBM-1047 >> data/data.txt
chtag -tc 1047 data/data.txt

# Stash without specifying file (should work)
$GIT_BIN stash 2>/dev/null

TAG3=$(chtag -p data/data.txt 2>/dev/null | awk '{print $2}')

if [ "$TAG3" = "IBM-1047" ]; then
    tap_result "ok" "git stash (no file arg) preserves IBM-1047 tag"
else
    tap_result "not ok" "git stash (no file arg) preserves IBM-1047 tag" "got: $TAG3, expected: IBM-1047"
fi

# Clean up
cd /
rm -rf "$TEST_ROOT"

exit $FAIL_COUNT
