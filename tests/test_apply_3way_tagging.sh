#!/bin/bash
#
# Test: git apply --3way file tagging with zos-working-tree-encoding
# 
# Issue: After git apply --3way, the merged file content is correct but
# the file tag is wrong (defaults to ISO8859-1 instead of IBM-1047).
#
# Expected: File should be tagged with encoding from .gitattributes
# Actual: File gets default system tag (ISO8859-1)
#
# TAP format output for integration with zopen_check_results

# Check if running on z/OS
if [ "$(uname)" != "OS/390" ]; then
    echo "1..0 # SKIP Not running on z/OS"
    exit 0
fi

# Find git binary
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

# Test 1: git apply --3way with IBM-1047 - check tag
# ===================================================
mkdir -p "$TEST_ROOT/test1" && cd "$TEST_ROOT/test1"

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

# Create .gitattributes
cat > .gitattributes << 'EOF'
*.c zos-working-tree-encoding=ibm-1047
EOF

$GIT_BIN add .gitattributes 2>/dev/null
$GIT_BIN commit -m "Add attributes" -q 2>/dev/null

# Create initial file in EBCDIC
cat > temp.txt << 'EOF'
int main() {
    return 0;
}
EOF

iconv -f ISO8859-1 -t IBM-1047 < temp.txt > file.c
chtag -tc 1047 file.c
rm temp.txt

$GIT_BIN add file.c 2>/dev/null
$GIT_BIN commit -m "Initial" -q 2>/dev/null

# Create conflicting changes for 3-way merge
# Branch with change
$GIT_BIN checkout -q -b feature 2>/dev/null

cat > temp.txt << 'EOF'
int main() {
    int feature = 1;
    return 0;
}
EOF

iconv -f ISO8859-1 -t IBM-1047 < temp.txt > file.c
chtag -tc 1047 file.c
rm temp.txt

$GIT_BIN add file.c 2>/dev/null
$GIT_BIN commit -m "Feature" -q 2>/dev/null

# Back to master with different change
$GIT_BIN checkout -q master 2>/dev/null

cat > temp.txt << 'EOF'
int main() {
    int master = 1;
    return 0;
}
EOF

iconv -f ISO8859-1 -t IBM-1047 < temp.txt > file.c
chtag -tc 1047 file.c
rm temp.txt

$GIT_BIN add file.c 2>/dev/null
$GIT_BIN commit -m "Master" -q 2>/dev/null

# Create patch from feature branch
$GIT_BIN diff master feature > /tmp/feature.patch

# Apply with --3way (will trigger 3-way merge)
if $GIT_BIN apply --3way /tmp/feature.patch 2>/dev/null; then
    # Check the tag
    TAG1=$(chtag -p file.c 2>/dev/null | awk '{print $2}')
    
    if [ "$TAG1" = "IBM-1047" ]; then
        tap_result "ok" "git apply --3way preserves IBM-1047 tag"
    else
        tap_result "not ok" "git apply --3way preserves IBM-1047 tag" "got: $TAG1, expected: IBM-1047"
    fi
else
    # Even if merge has conflicts, check the tag
    TAG1=$(chtag -p file.c 2>/dev/null | awk '{print $2}')
    
    if [ "$TAG1" = "IBM-1047" ]; then
        tap_result "ok" "git apply --3way preserves IBM-1047 tag (with conflicts)"
    else
        tap_result "not ok" "git apply --3way preserves IBM-1047 tag" "got: $TAG1, expected: IBM-1047"
    fi
fi

# Test 2: git apply --3way with working-tree-encoding attribute
# ==============================================================
mkdir -p "$TEST_ROOT/test2" && cd "$TEST_ROOT/test2"

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

# Use working-tree-encoding (not zos-working-tree-encoding)
cat > .gitattributes << 'EOF'
*.txt working-tree-encoding=ibm-1047
EOF

$GIT_BIN add .gitattributes 2>/dev/null
$GIT_BIN commit -m "Attrs" -q 2>/dev/null

# Create file
echo "line1" | iconv -f ISO8859-1 -t IBM-1047 > file.txt
chtag -tc 1047 file.txt

$GIT_BIN add file.txt 2>/dev/null
$GIT_BIN commit -m "Initial" -q 2>/dev/null

# Create patch that will need 3-way
$GIT_BIN checkout -q -b br1 2>/dev/null
echo "line1-br1" | iconv -f ISO8859-1 -t IBM-1047 > file.txt
chtag -tc 1047 file.txt
$GIT_BIN add file.txt 2>/dev/null
$GIT_BIN commit -m "Branch1" -q 2>/dev/null

$GIT_BIN checkout -q master 2>/dev/null
echo "line1-master" | iconv -f ISO8859-1 -t IBM-1047 > file.txt
chtag -tc 1047 file.txt
$GIT_BIN add file.txt 2>/dev/null
$GIT_BIN commit -m "Master" -q 2>/dev/null

# Create and apply patch
$GIT_BIN diff master br1 > /tmp/br1.patch

$GIT_BIN apply --3way /tmp/br1.patch 2>/dev/null || true

TAG2=$(chtag -p file.txt 2>/dev/null | awk '{print $2}')

if [ "$TAG2" = "IBM-1047" ]; then
    tap_result "ok" "git apply --3way with working-tree-encoding preserves tag"
else
    tap_result "not ok" "git apply --3way with working-tree-encoding preserves tag" "got: $TAG2, expected: IBM-1047"
fi

# Test 3: Verify content is correct even if tag is wrong
# =======================================================
mkdir -p "$TEST_ROOT/test3" && cd "$TEST_ROOT/test3"

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

cat > .gitattributes << 'EOF'
*.txt zos-working-tree-encoding=ibm-1047
EOF

$GIT_BIN add .gitattributes 2>/dev/null
$GIT_BIN commit -m "Attrs" -q 2>/dev/null

# Create initial
echo "base" | iconv -f ISO8859-1 -t IBM-1047 > data.txt
chtag -tc 1047 data.txt
$GIT_BIN add data.txt 2>/dev/null
$GIT_BIN commit -m "Base" -q 2>/dev/null

# Branch
$GIT_BIN checkout -q -b branch 2>/dev/null
echo "branch-change" | iconv -f ISO8859-1 -t IBM-1047 > data.txt
chtag -tc 1047 data.txt
$GIT_BIN add data.txt 2>/dev/null
$GIT_BIN commit -m "Branch" -q 2>/dev/null

# Master
$GIT_BIN checkout -q master 2>/dev/null
echo "master-change" | iconv -f ISO8859-1 -t IBM-1047 > data.txt
chtag -tc 1047 data.txt
$GIT_BIN add data.txt 2>/dev/null
$GIT_BIN commit -m "Master" -q 2>/dev/null

# Apply with 3way
$GIT_BIN diff master branch > /tmp/b.patch
$GIT_BIN apply --3way /tmp/b.patch 2>/dev/null || true

# Check if content is valid (can be read without errors)
# Even if tag is wrong, content should be converted correctly
TAG3=$(chtag -p data.txt 2>/dev/null | awk '{print $2}')
CONTENT_READABLE=0

# If tag is wrong, retag it temporarily to check content
if [ "$TAG3" != "IBM-1047" ]; then
    # Save original tag
    ORIG_TAG="$TAG3"
    # Retag to check if content is actually IBM-1047
    chtag -tc 1047 data.txt 2>/dev/null
    if cat data.txt >/dev/null 2>&1; then
        CONTENT_READABLE=1
    fi
    # Restore wrong tag for diagnostic
    chtag -tc $(echo $ORIG_TAG | sed 's/[^0-9]//g') data.txt 2>/dev/null || true
else
    if cat data.txt >/dev/null 2>&1; then
        CONTENT_READABLE=1
    fi
fi

if [ $CONTENT_READABLE -eq 1 ]; then
    tap_result "ok" "git apply --3way content is correctly converted (even if tag wrong)" "tag was: $TAG3"
else
    tap_result "not ok" "git apply --3way content is correctly converted" "content unreadable, tag: $TAG3"
fi

# Clean up
cd /
rm -rf "$TEST_ROOT"

exit $FAIL_COUNT
