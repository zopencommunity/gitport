#!/bin/bash
#
# Test: Three-level attribute precedence hierarchy
# 
# This test verifies Git attribute precedence when multiple patterns match:
# 1. Global wildcard (*)
# 2. Extension wildcard (*.txt)
# 3. Specific file (special.txt)
#
# Tests both encoding and binary attributes with all precedence levels.
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
echo "1..7"

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

# Test: Three-level precedence with encodings and binary
# =======================================================
cd "$TEST_ROOT"
mkdir test1 && cd test1

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

# Create comprehensive .gitattributes with three levels
cat << 'EOF' > .gitattributes
# Level 1: Global wildcard
* text working-tree-encoding=UTF-8

# Level 2: Extension-specific
*.txt text zos-working-tree-encoding=IBM-1047
*.dat text zos-working-tree-encoding=IBM-037

# Level 3: File-specific overrides
special.txt binary
specific.dat -text zos-working-tree-encoding=ISO8859-1
EOF

# Create test files
echo "Default file" > default.log       # Should get UTF-8 from *
echo "Text file" > regular.txt          # Should get IBM-1047 from *.txt
echo "Data file" > data.dat             # Should get IBM-037 from *.dat
echo "Special text" > special.txt       # Should be binary (overrides *.txt)
echo "Specific data" > specific.dat     # Should get ISO8859-1 (overrides *.dat)
echo "Another text" > another.txt       # Should get IBM-1047 from *.txt
echo "Config file" > config.cfg         # Should get UTF-8 from *

$GIT_BIN add .gitattributes *.log *.txt *.dat *.cfg 2>/dev/null
$GIT_BIN commit -m "test" -q 2>/dev/null

# Remove and checkout
rm -f *.log *.txt *.dat *.cfg
$GIT_BIN checkout HEAD . 2>/dev/null

# Check tags
TAG_DEFAULT=$(chtag -p default.log 2>/dev/null | awk '{print $2}')
TAG_REGULAR=$(chtag -p regular.txt 2>/dev/null | awk '{print $2}')
TAG_DATA=$(chtag -p data.dat 2>/dev/null | awk '{print $2}')
TAG_SPECIAL=$(chtag -p special.txt 2>/dev/null | awk '{print $1, $2}')
TAG_SPECIFIC=$(chtag -p specific.dat 2>/dev/null | awk '{print $2}')
TAG_ANOTHER=$(chtag -p another.txt 2>/dev/null | awk '{print $2}')
TAG_CONFIG=$(chtag -p config.cfg 2>/dev/null | awk '{print $2}')

# Get expected UTF-8 tag based on GIT_UTF8_CCSID
EXPECTED_UTF8=$(get_expected_utf8_tag)

# Test results
if is_expected_utf8_tag "$TAG_DEFAULT"; then
    tap_result "ok" "Level 1 (global *): default.log tagged as $EXPECTED_UTF8"
else
    tap_result "not ok" "Level 1 (global *): default.log tagged as $EXPECTED_UTF8" "got: $TAG_DEFAULT, expected: $EXPECTED_UTF8"
fi

if [ "$TAG_REGULAR" = "IBM-1047" ]; then
    tap_result "ok" "Level 2 (*.txt): regular.txt tagged as IBM-1047"
else
    tap_result "not ok" "Level 2 (*.txt): regular.txt tagged as IBM-1047" "got: $TAG_REGULAR, expected: IBM-1047"
fi

if [ "$TAG_DATA" = "IBM-037" ]; then
    tap_result "ok" "Level 2 (*.dat): data.dat tagged as IBM-037"
else
    tap_result "not ok" "Level 2 (*.dat): data.dat tagged as IBM-037" "got: $TAG_DATA, expected: IBM-037"
fi

if echo "$TAG_SPECIAL" | grep -q "b binary"; then
    tap_result "ok" "Level 3 (specific file): special.txt binary overrides *.txt encoding"
else
    tap_result "not ok" "Level 3 (specific file): special.txt binary overrides *.txt encoding" "got: $TAG_SPECIAL, expected: b binary"
fi

if [ "$TAG_SPECIFIC" = "ISO8859-1" ]; then
    tap_result "ok" "Level 3 (specific file): specific.dat encoding overrides *.dat encoding"
else
    tap_result "not ok" "Level 3 (specific file): specific.dat encoding overrides *.dat encoding" "got: $TAG_SPECIFIC, expected: ISO8859-1"
fi

if [ "$TAG_ANOTHER" = "IBM-1047" ]; then
    tap_result "ok" "Level 2 consistency: another.txt also gets IBM-1047"
else
    tap_result "not ok" "Level 2 consistency: another.txt also gets IBM-1047" "got: $TAG_ANOTHER, expected: IBM-1047"
fi

if is_expected_utf8_tag "$TAG_CONFIG"; then
    tap_result "ok" "Level 1 consistency: config.cfg gets $EXPECTED_UTF8"
else
    tap_result "not ok" "Level 1 consistency: config.cfg gets $EXPECTED_UTF8" "got: $TAG_CONFIG, expected: $EXPECTED_UTF8"
fi

# Clean up
cd /
rm -rf "$TEST_ROOT"

exit $FAIL_COUNT
