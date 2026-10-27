#!/bin/bash
#
# Test: git rerere with cherry-pick and zos-working-tree-encoding
# 
# Issue: When rerere auto-resolves conflicts after cherry-pick,
# files lose their zos-working-tree-encoding tag
#
# Expected: File should retain IBM-1047 tag after rerere resolution
# Actual: File gets default ISO8859-1 tag
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
echo "1..2"

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

# Test 1: cherry-pick with conflict, manual resolution
# ====================================================
mkdir -p "$TEST_ROOT/test1" && cd "$TEST_ROOT/test1"

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false
$GIT_BIN config rerere.enabled true

# Create .gitattributes
cat > .gitattributes << 'EOF'
*.txt zos-working-tree-encoding=ibm-1047
EOF

# Create initial file in EBCDIC
cat > temp.txt << 'EOF'
line 1
line 2
line 3
EOF

iconv -f ISO8859-1 -t IBM-1047 < temp.txt > file.txt
chtag -tc 1047 file.txt
rm temp.txt

$GIT_BIN add .gitattributes file.txt 2>/dev/null
$GIT_BIN commit -m "Initial" -q 2>/dev/null

# Create branch with changes
$GIT_BIN checkout -q -b feature 2>/dev/null

cat > temp.txt << 'EOF'
line 1 - feature
line 2
line 3
EOF

iconv -f ISO8859-1 -t IBM-1047 < temp.txt > file.txt
chtag -tc 1047 file.txt
rm temp.txt

$GIT_BIN add file.txt 2>/dev/null
$GIT_BIN commit -m "Feature change" -q 2>/dev/null

# Go back to main and make conflicting change
$GIT_BIN checkout -q main 2>/dev/null

cat > temp.txt << 'EOF'
line 1 - main
line 2
line 3
EOF

iconv -f ISO8859-1 -t IBM-1047 < temp.txt > file.txt
chtag -tc 1047 file.txt
rm temp.txt

$GIT_BIN add file.txt 2>/dev/null
$GIT_BIN commit -m "Main change" -q 2>/dev/null

# Cherry-pick (will conflict)
if ! $GIT_BIN cherry-pick feature 2>/dev/null; then
    # Resolve conflict
    cat > temp.txt << 'EOF'
line 1 - resolved
line 2
line 3
EOF
    
    iconv -f ISO8859-1 -t IBM-1047 < temp.txt > file.txt
    chtag -tc 1047 file.txt
    rm temp.txt
    
    $GIT_BIN add file.txt 2>/dev/null
    $GIT_BIN cherry-pick --continue -m "Resolved" -q 2>/dev/null
    
    # Check tag
    TAG1=$(chtag -p file.txt 2>/dev/null | awk '{print $2}')
    
    if [ "$TAG1" = "IBM-1047" ]; then
        tap_result "ok" "cherry-pick conflict resolution preserves IBM-1047 tag"
    else
        tap_result "not ok" "cherry-pick conflict resolution preserves IBM-1047 tag" "got: $TAG1, expected: IBM-1047"
    fi
else
    tap_result "not ok" "cherry-pick conflict resolution preserves IBM-1047 tag" "no conflict occurred"
fi

# Test 2: cherry-pick with rerere auto-resolve
# =============================================
mkdir -p "$TEST_ROOT/test2" && cd "$TEST_ROOT/test2"

$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false
$GIT_BIN config rerere.enabled true

cat > .gitattributes << 'EOF'
*.txt zos-working-tree-encoding=ibm-1047
EOF

# Create initial file
echo "base" | iconv -f ISO8859-1 -t IBM-1047 > data.txt
chtag -tc 1047 data.txt

$GIT_BIN add .gitattributes data.txt 2>/dev/null
$GIT_BIN commit -m "Initial" -q 2>/dev/null

# Branch A
$GIT_BIN checkout -q -b branchA 2>/dev/null
echo "branch A" | iconv -f ISO8859-1 -t IBM-1047 > data.txt
chtag -tc 1047 data.txt
$GIT_BIN add data.txt 2>/dev/null
$GIT_BIN commit -m "Branch A" -q 2>/dev/null

# Main conflict
$GIT_BIN checkout -q main 2>/dev/null
echo "main change" | iconv -f ISO8859-1 -t IBM-1047 > data.txt
chtag -tc 1047 data.txt
$GIT_BIN add data.txt 2>/dev/null
$GIT_BIN commit -m "Main" -q 2>/dev/null

# First cherry-pick (record resolution in rerere)
if ! $GIT_BIN cherry-pick branchA 2>/dev/null; then
    echo "resolved" | iconv -f ISO8859-1 -t IBM-1047 > data.txt
    chtag -tc 1047 data.txt
    $GIT_BIN add data.txt 2>/dev/null
    $GIT_BIN cherry-pick --continue -m "First" -q 2>/dev/null
fi

# Reset and cherry-pick again (rerere should auto-resolve)
$GIT_BIN reset --hard HEAD~1 -q 2>/dev/null

if ! $GIT_BIN cherry-pick branchA 2>/dev/null; then
    # Rerere should have helped
    $GIT_BIN add data.txt 2>/dev/null
    $GIT_BIN cherry-pick --continue -m "Second with rerere" -q 2>/dev/null
fi

# Check tag after rerere auto-resolve
TAG2=$(chtag -p data.txt 2>/dev/null | awk '{print $2}')

if [ "$TAG2" = "IBM-1047" ]; then
    tap_result "ok" "rerere auto-resolve preserves IBM-1047 tag"
else
    tap_result "not ok" "rerere auto-resolve preserves IBM-1047 tag" "got: $TAG2, expected: IBM-1047"
fi

# Clean up
cd /
rm -rf "$TEST_ROOT"

exit $FAIL_COUNT
