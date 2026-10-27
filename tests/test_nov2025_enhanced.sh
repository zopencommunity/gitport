#!/bin/bash
#
# Enhanced test: Verify the Nov 2025 issue with IBM-1047 vs ISO8859-1
# This test uses actual different encodings to see if the issue exists
#

set -e

echo "=========================================="
echo "Enhanced Test: Nov 2025 Issue"
echo "Testing with actual IBM-1047 content"
echo "=========================================="
echo

# Setup test directory
TEST_DIR="/tmp/test_nov2025_enhanced_$$"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Check if we have a working git with z/OS encoding support
GIT_VERSION=$(git --version)
echo "Git version: $GIT_VERSION"
echo

echo "Step 1: Initialize repository"
git init
git config user.name "Test User"
git config user.email "test@test.com"
echo

echo "Step 2: Create .gitattributes specifying IBM-1047 for yml files"
cat > .gitattributes << 'EOF'
* zos-working-tree-encoding=iso8859-1
*.yml zos-working-tree-encoding=ibm-1047 git-encoding=utf-8
EOF
git add .gitattributes
git commit -m "Initial .gitattributes with IBM-1047 for yml"
echo

echo "Step 3: Create config.yml with content that will show encoding differences"
# Create file with special characters that differ between encodings
cat > config.yml << 'EOF'
name: "Test Config"
value: 123
special: "ä ö ü"
EOF

# Manually tag as IBM-1047 to simulate what should happen
echo "Manually tagging config.yml as IBM-1047 to simulate initial state..."
chtag -tc IBM-1047 config.yml
echo "File tag after manual tagging:"
chtag -p config.yml
echo

git add config.yml
git commit -m "Add config.yml (IBM-1047)"
echo

echo "Step 4: Verify initial state"
echo "config.yml tag:"
chtag -p config.yml
TAG_INITIAL=$(chtag -p config.yml 2>&1 | awk '{print $2}')
echo "  Initial tag: $TAG_INITIAL"
echo

# Check what git thinks about the file
echo "Git check-attr:"
git check-attr -a config.yml
echo

echo "=========================================="
echo "User fixes .gitattributes"
echo "=========================================="
echo

echo "Step 5: Change .gitattributes to ISO8859-1"
cat > .gitattributes << 'EOF'
* zos-working-tree-encoding=iso8859-1
*.yml zos-working-tree-encoding=ISO8859-1 git-encoding=utf-8
EOF
git add .gitattributes
git commit -m "Fix: Change yml to ISO8859-1"
echo

echo "Step 6: Check file tag (should NOT change automatically)"
chtag -p config.yml
TAG_AFTER_FIX=$(chtag -p config.yml 2>&1 | awk '{print $2}')
echo "  Tag after .gitattributes fix: $TAG_AFTER_FIX"

if [ "$TAG_AFTER_FIX" = "$TAG_INITIAL" ]; then
    echo "  ✅ Correct - tag didn't change (expected behavior)"
else
    echo "  ⚠️ Tag changed unexpectedly!"
fi
echo

echo "=========================================="
echo "User deletes and recreates file"
echo "=========================================="
echo

echo "Step 7: Delete config.yml"
git rm -f config.yml
git commit -m "Delete config.yml"
echo "  ✅ Deleted"
echo

echo "Step 8: Create NEW file with different name (control test)"
cat > control.yml << 'EOF'
name: "Control File"
value: 999
EOF
git add control.yml
git commit -m "Add control.yml"
echo

echo "Control file tag:"
chtag -p control.yml
TAG_CONTROL=$(chtag -p control.yml 2>&1 | awk '{print $2}')
echo "  Control tag: $TAG_CONTROL (should be ISO8859-1)"
echo

echo "Step 9: Recreate config.yml with SAME NAME"
cat > config.yml << 'EOF'
name: "Test Config"
value: 123
special: "ä ö ü"
EOF
git add config.yml
git commit -m "Recreate config.yml"
echo

echo "Step 10: THE TEST - Check recreated file tag"
chtag -p config.yml
TAG_RECREATED=$(chtag -p config.yml 2>&1 | awk '{print $2}')
echo "  Recreated tag: $TAG_RECREATED"
echo

echo "=========================================="
echo "ANALYSIS"
echo "=========================================="
echo
echo "Timeline:"
echo "  1. Initial tag (IBM-1047):      $TAG_INITIAL"
echo "  2. After .gitattributes change: $TAG_AFTER_FIX"
echo "  3. Control file (new name):     $TAG_CONTROL"
echo "  4. Recreated (same name):       $TAG_RECREATED"
echo
echo "Expected behavior after fix:"
echo "  - Control file should be:  ISO8859-1"
echo "  - Recreated file should be: ISO8859-1"
echo
echo "Issue exists if:"
echo "  - Recreated file is: IBM-1047 (old encoding)"
echo

if [ "$TAG_RECREATED" = "ISO8859-1" ]; then
    if [ "$TAG_INITIAL" = "IBM-1047" ]; then
        echo "✅✅✅ ISSUE IS FIXED! ✅✅✅"
        echo "Recreated file correctly uses new .gitattributes encoding"
    else
        echo "⚠️ Test inconclusive - initial tag was not IBM-1047"
        echo "Need to verify git is actually applying IBM-1047 from .gitattributes"
    fi
elif [ "$TAG_RECREATED" = "IBM-1047" ]; then
    echo "❌❌❌ ISSUE STILL EXISTS! ❌❌❌"
    echo "Recreated file incorrectly uses old encoding"
    echo "Git is somehow remembering the old tag"
else
    echo "⚠️ Unexpected tag: $TAG_RECREATED"
fi

echo
echo "=========================================="
echo "Additional Checks"
echo "=========================================="
echo

echo "Git status:"
git status --short
echo

echo "Git attributes for both files:"
git check-attr -a config.yml control.yml
echo

echo "File contents comparison:"
echo "config.yml:"
iconv -f IBM-1047 -t UTF-8 config.yml 2>/dev/null || cat config.yml
echo
echo "control.yml:"
iconv -f ISO8859-1 -t UTF-8 control.yml 2>/dev/null || cat control.yml
echo

echo "=========================================="
echo "Test directory: $TEST_DIR"
echo "To inspect: cd $TEST_DIR"
echo "To cleanup: rm -rf $TEST_DIR"
