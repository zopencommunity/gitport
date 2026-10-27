#!/bin/bash
#
# Test: EOL + Encoding combinations
# 
# This test verifies that -text with explicit eol= still respects encoding.
# Use case: Windows scripts that must keep CRLF on z/OS, but need encoding tags.
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

# Source shared helper functions
source "$SCRIPT_DIR/test_helpers.sh"

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

# Clean up from helper functions
rm -rf "$TEST_ROOT"
mkdir -p "$TEST_ROOT"  # Recreate before tests

# Test 1: -text eol=crlf with encoding
# =====================================
cd "$TEST_ROOT"
mkdir test1 && cd test1

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

cat << 'EOF' > .gitattributes
*.bat -text eol=crlf zos-working-tree-encoding=ISO8859-1
EOF

echo "echo Hello" > script.bat
chtag -tc 819 script.bat

$GIT_BIN add .gitattributes script.bat 2>/dev/null
$GIT_BIN commit -m "test" -q 2>/dev/null

rm script.bat
$GIT_BIN checkout HEAD script.bat 2>/dev/null

TAG1=$(chtag -p script.bat 2>/dev/null | awk '{print $2}')

if [ "$TAG1" = "ISO8859-1" ]; then
    tap_result "ok" "-text eol=crlf + encoding tags as ISO8859-1"
else
    tap_result "not ok" "-text eol=crlf + encoding tags as ISO8859-1" "got: $TAG1, expected: ISO8859-1"
fi

cd "$TEST_ROOT"

# Test 2: -text eol=lf with encoding
# ===================================
mkdir test2 && cd test2

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

cat << 'EOF' > .gitattributes
*.sh -text eol=lf zos-working-tree-encoding=ISO8859-1
EOF

echo "#!/bin/bash" > script.sh
chtag -tc 819 script.sh

$GIT_BIN add .gitattributes script.sh 2>/dev/null
$GIT_BIN commit -m "test" -q 2>/dev/null

rm script.sh
$GIT_BIN checkout HEAD script.sh 2>/dev/null

TAG2=$(chtag -p script.sh 2>/dev/null | awk '{print $2}')

if [ "$TAG2" = "ISO8859-1" ]; then
    tap_result "ok" "-text eol=lf + encoding tags as ISO8859-1"
else
    tap_result "not ok" "-text eol=lf + encoding tags as ISO8859-1" "got: $TAG2, expected: ISO8859-1"
fi

cd "$TEST_ROOT"

# Test 3: text eol=crlf with encoding
# ====================================
mkdir test3 && cd test3

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

cat << 'EOF' > .gitattributes
*.cmd text eol=crlf zos-working-tree-encoding=IBM-1047
EOF

echo "REM Windows command" > script.cmd
chtag -tc 1047 script.cmd

$GIT_BIN add .gitattributes script.cmd 2>/dev/null
$GIT_BIN commit -m "test" -q 2>/dev/null

rm script.cmd
$GIT_BIN checkout HEAD script.cmd 2>/dev/null

TAG3=$(chtag -p script.cmd 2>/dev/null | awk '{print $2}')

if [ "$TAG3" = "IBM-1047" ]; then
    tap_result "ok" "text eol=crlf + encoding tags as IBM-1047"
else
    tap_result "not ok" "text eol=crlf + encoding tags as IBM-1047" "got: $TAG3, expected: IBM-1047"
fi

cd "$TEST_ROOT"

# Test 4: text eol=lf with encoding
# ==================================
mkdir test4 && cd test4

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

cat << 'EOF' > .gitattributes
*.pl text eol=lf zos-working-tree-encoding=UTF-8
EOF

echo "#!/usr/bin/perl" > script.pl
chtag -tc UTF-8 script.pl

$GIT_BIN add .gitattributes script.pl 2>/dev/null
$GIT_BIN commit -m "test" -q 2>/dev/null

rm script.pl
$GIT_BIN checkout HEAD script.pl 2>/dev/null

TAG4=$(chtag -p script.pl 2>/dev/null | awk '{print $2}')

# Get expected UTF-8 tag
EXPECTED_UTF8=$(get_expected_utf8_tag)

if is_expected_utf8_tag "$TAG4"; then
    tap_result "ok" "text eol=lf + encoding tags as $EXPECTED_UTF8"
else
    tap_result "not ok" "text eol=lf + encoding tags as $EXPECTED_UTF8" "got: $TAG4, expected: $EXPECTED_UTF8"
fi

# Clean up
cd /
rm -rf "$TEST_ROOT"

exit $FAIL_COUNT
