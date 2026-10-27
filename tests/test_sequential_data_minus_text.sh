#!/bin/bash
#
# Test: Sequential data files with -text + encoding (Issue #3)
# 
# This test verifies handling of fixed-length record files (like mainframe
# sequential datasets) that:
# - Cannot have EOL conversion (would break fixed-length records)
# - Need encoding conversion for Git storage
# - Use -text to disable EOL, but still need encoding tag
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
echo "1..6"

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

# Clean up
rm -rf "$TEST_ROOT"

# Test 1: Sequential dataset with IBM-1047
# =========================================
cd "$TEST_ROOT"
mkdir test1 && cd test1

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

cat << 'EOF' > .gitattributes
*.seq -text zos-working-tree-encoding=IBM-1047
EOF

# Create a sequential dataset file (80-byte fixed records, EBCDIC)
# Each line is exactly 80 bytes (no newlines, fixed length)
cat > dataset.seq << 'DATA'
RECORD 001                                                                      RECORD 002                                                                      RECORD 003                                                                      DATA

chtag -tc 1047 dataset.seq

$GIT_BIN add .gitattributes dataset.seq 2>/dev/null
$GIT_BIN commit -m "test" -q 2>/dev/null

rm dataset.seq
$GIT_BIN checkout HEAD dataset.seq 2>/dev/null

TAG1=$(chtag -p dataset.seq 2>/dev/null | awk '{print $2}')

if [ "$TAG1" = "IBM-1047" ]; then
    tap_result "ok" "Sequential dataset (1047) tagged correctly"
else
    tap_result "not ok" "Sequential dataset (1047) tagged correctly" "got: $TAG1, expected: IBM-1047"
fi

cd "$TEST_ROOT"

# Test 2: Sequential dataset with IBM-037
# =========================================
mkdir test2 && cd test2

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

cat << 'EOF' > .gitattributes
*.dat -text zos-working-tree-encoding=IBM-037
EOF

# Create data file in IBM-037
cat > data.dat << 'DATA'
DATA001                                                                         DATA002                                                                         DATA

chtag -tc 37 data.dat

$GIT_BIN add .gitattributes data.dat 2>/dev/null
$GIT_BIN commit -m "test" -q 2>/dev/null

rm data.dat
$GIT_BIN checkout HEAD data.dat 2>/dev/null

TAG2=$(chtag -p data.dat 2>/dev/null | awk '{print $2}')

if [ "$TAG2" = "IBM-037" ]; then
    tap_result "ok" "Sequential dataset (037) tagged correctly"
else
    tap_result "not ok" "Sequential dataset (037) tagged correctly" "got: $TAG2, expected: IBM-037"
fi

cd "$TEST_ROOT"

# Test 3: Multiple sequential files with different encodings
# ===========================================================
mkdir test3 && cd test3

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

cat << 'EOF' > .gitattributes
*.seq -text zos-working-tree-encoding=IBM-1047
*.dat -text zos-working-tree-encoding=IBM-037
*.fix -text zos-working-tree-encoding=ISO8859-1
EOF

# Create files
echo "SEQ FILE" > file1.seq
chtag -tc 1047 file1.seq

echo "DAT FILE" > file2.dat
chtag -tc 37 file2.dat

echo "FIX FILE" > file3.fix
chtag -tc 819 file3.fix

$GIT_BIN add .gitattributes file1.seq file2.dat file3.fix 2>/dev/null
$GIT_BIN commit -m "test" -q 2>/dev/null

rm file1.seq file2.dat file3.fix
$GIT_BIN checkout HEAD . 2>/dev/null

TAG_SEQ=$(chtag -p file1.seq 2>/dev/null | awk '{print $2}')
TAG_DAT=$(chtag -p file2.dat 2>/dev/null | awk '{print $2}')
TAG_FIX=$(chtag -p file3.fix 2>/dev/null | awk '{print $2}')

if [ "$TAG_SEQ" = "IBM-1047" ]; then
    tap_result "ok" "Multi-encoding: .seq file tagged as IBM-1047"
else
    tap_result "not ok" "Multi-encoding: .seq file tagged as IBM-1047" "got: $TAG_SEQ, expected: IBM-1047"
fi

if [ "$TAG_DAT" = "IBM-037" ]; then
    tap_result "ok" "Multi-encoding: .dat file tagged as IBM-037"
else
    tap_result "not ok" "Multi-encoding: .dat file tagged as IBM-037" "got: $TAG_DAT, expected: IBM-037"
fi

if [ "$TAG_FIX" = "ISO8859-1" ]; then
    tap_result "ok" "Multi-encoding: .fix file tagged as ISO8859-1"
else
    tap_result "not ok" "Multi-encoding: .fix file tagged as ISO8859-1" "got: $TAG_FIX, expected: ISO8859-1"
fi

cd "$TEST_ROOT"

# Test 4: Mixed codepage file (both ASCII and EBCDIC in same file)
# =================================================================
mkdir test4 && cd test4

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

cat << 'EOF' > .gitattributes
*.mixed -text zos-working-tree-encoding=IBM-1047
EOF

# Create a file with mixed content (simulating Issue #3 scenario)
# This would have some ASCII and some EBCDIC characters
cat > data.mixed << 'EOF'
MIXED CONTENT FILE
SOME ASCII CHARACTERS: ABC123
SOME EBCDIC CHARACTERS: XYZ789
EOF

chtag -tc 1047 data.mixed

$GIT_BIN add .gitattributes data.mixed 2>/dev/null
$GIT_BIN commit -m "test" -q 2>/dev/null

rm data.mixed
$GIT_BIN checkout HEAD data.mixed 2>/dev/null

TAG_MIXED=$(chtag -p data.mixed 2>/dev/null | awk '{print $2}')

if [ "$TAG_MIXED" = "IBM-1047" ]; then
    tap_result "ok" "Mixed codepage file tagged as IBM-1047 (not binary)"
else
    tap_result "not ok" "Mixed codepage file tagged as IBM-1047 (not binary)" "got: $TAG_MIXED, expected: IBM-1047"
fi

# Clean up
cd /
rm -rf "$TEST_ROOT"

exit $FAIL_COUNT
