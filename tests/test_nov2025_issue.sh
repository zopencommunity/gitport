#!/bin/bash
#
# Test: Reproduce the exact issue reported in Nov 2025
# User scenario: Changed .gitattributes, deleted file, recreated file
#                File kept old encoding tag instead of new one
#

set -e

echo "=========================================="
echo "Reproducing Issue Reported Nov 2025"
echo "=========================================="
echo

# Setup test directory
TEST_DIR="/tmp/test_nov2025_issue_$$"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo "Step 1: Initialize git repository (simulating user's repository)"
git init
git config user.name "Test User"
git config user.email "test@test.com"
echo

echo "Step 2: Create .gitattributes with WRONG encoding (user's mistake)"
echo "User had: *.yml zos-working-tree-encoding=ibm-1047 git-encoding=utf-8"
cat > .gitattributes << 'EOF'
* zos-working-tree-encoding=iso8859-1
*.yml zos-working-tree-encoding=ibm-1047 git-encoding=utf-8
EOF
git add .gitattributes
git commit -m "Initial .gitattributes (wrong encoding)"
echo

echo "Step 3: Create config.yml file"
cat > config.yml << 'EOF'
server:
  host: localhost
  port: 8080
database:
  name: mydb
  user: admin
EOF
git add config.yml
git commit -m "Add config.yml"
echo

echo "Step 4: Check file tag (should be IBM-1047 due to .gitattributes)"
echo "config.yml tag:"
chtag -p config.yml
TAG_BEFORE=$(chtag -p config.yml 2>&1 | awk '{print $2}')
echo "  Tag: $TAG_BEFORE"
echo

echo "=========================================="
echo "User discovers the mistake and fixes it"
echo "=========================================="
echo

echo "Step 5: User changes .gitattributes to correct encoding"
echo "Changed to: *.yml zos-working-tree-encoding=ISO8859-1 git-encoding=utf-8"
cat > .gitattributes << 'EOF'
* zos-working-tree-encoding=iso8859-1
*.yml zos-working-tree-encoding=ISO8859-1 git-encoding=utf-8
EOF
git add .gitattributes
git commit -m "Fix: Change yml encoding to ISO8859-1"
echo

echo "Step 6: User checks file - still has old tag (expected)"
echo "config.yml tag after .gitattributes change:"
chtag -p config.yml
TAG_AFTER_CHANGE=$(chtag -p config.yml 2>&1 | awk '{print $2}')
echo "  Tag: $TAG_AFTER_CHANGE"
echo "  ℹ️  This is EXPECTED - Git doesn't auto-retag existing files"
echo

echo "=========================================="
echo "User tries to fix by deleting and recreating"
echo "=========================================="
echo

echo "Step 7: User deletes the yaml file"
git rm -f config.yml
git commit -m "Delete config.yml"
echo "  ✅ File deleted and committed"
echo

echo "Step 8: User creates a NEW test file to verify it works"
cat > test-new.yml << 'EOF'
test: newfile
status: working
EOF
git add test-new.yml
git commit -m "Add test-new.yml (brand new file)"
echo

echo "Check test-new.yml tag:"
chtag -p test-new.yml
TAG_NEW_FILE=$(chtag -p test-new.yml 2>&1 | awk '{print $2}')
echo "  Tag: $TAG_NEW_FILE"
if [ "$TAG_NEW_FILE" = "ISO8859-1" ]; then
    echo "  ✅ GOOD - New file gets correct encoding"
else
    echo "  ❌ UNEXPECTED - New file got wrong encoding"
fi
echo

echo "Step 9: User re-creates the original config.yml"
echo "With same name and content as before"
cat > config.yml << 'EOF'
server:
  host: localhost
  port: 8080
database:
  name: mydb
  user: admin
EOF
git add config.yml
git commit -m "Re-create config.yml"
echo

echo "Step 10: THE BUG - Check if recreated file has correct tag"
echo "config.yml tag (recreated with same name):"
chtag -p config.yml
TAG_RECREATED=$(chtag -p config.yml 2>&1 | awk '{print $2}')
echo "  Tag: $TAG_RECREATED"
echo

echo "=========================================="
echo "RESULTS:"
echo "=========================================="
echo "1. Initial tag:           $TAG_BEFORE"
echo "2. After .gitattributes:  $TAG_AFTER_CHANGE (expected to stay same)"
echo "3. New file (test-new):   $TAG_NEW_FILE (should be ISO8859-1)"
echo "4. Recreated file:        $TAG_RECREATED (should be ISO8859-1)"
echo

if [ "$TAG_RECREATED" = "ISO8859-1" ]; then
    echo "✅✅✅ ISSUE IS FIXED! ✅✅✅"
    echo "The recreated file got the correct encoding from .gitattributes"
    echo
    RESULT="FIXED"
elif [ "$TAG_RECREATED" = "$TAG_BEFORE" ]; then
    echo "❌❌❌ ISSUE STILL EXISTS! ❌❌❌"
    echo "The recreated file kept the OLD encoding ($TAG_BEFORE)"
    echo "Expected: ISO8859-1"
    echo "Got:      $TAG_RECREATED"
    echo
    RESULT="NOT_FIXED"
else
    echo "⚠️⚠️⚠️ UNEXPECTED RESULT! ⚠️⚠️⚠️"
    echo "The recreated file has encoding: $TAG_RECREATED"
    echo "Expected: ISO8859-1"
    echo "This is different from both old and new!"
    echo
    RESULT="UNEXPECTED"
fi

echo "=========================================="
echo "Verification: Check git's internal state"
echo "=========================================="
echo

echo "Git attributes for config.yml:"
git check-attr -a config.yml
echo

echo "Git diff (should be clean):"
git diff config.yml
if [ $? -eq 0 ]; then
    echo "  ✅ No diff - file is clean"
else
    echo "  ⚠️ File shows as modified"
fi
echo

echo "=========================================="
echo "Test Complete: $RESULT"
echo "=========================================="
echo
echo "Test directory: $TEST_DIR"
echo
if [ "$RESULT" = "NOT_FIXED" ]; then
    echo "WORKAROUNDS TO FIX:"
    echo "  1. git checkout -- config.yml"
    echo "  2. chtag -tc ISO8859-1 config.yml"
    echo "  3. git rm --cached config.yml && git add config.yml"
    echo
    echo "Try workaround #1:"
    git checkout -- config.yml
    echo "After git checkout --:"
    chtag -p config.yml
fi

echo
echo "To inspect: cd $TEST_DIR"
echo "To cleanup: rm -rf $TEST_DIR"
