#!/bin/bash
#
# Final comprehensive test: Simulate the complete user workflow
# Including git push/pull scenario from the Nov 2025 issue
#

set -e

echo "=========================================="
echo "COMPREHENSIVE TEST: Nov 2025 Issue"
echo "Complete workflow with push/pull simulation"
echo "=========================================="
echo

# Setup directories
BASE_DIR="/tmp/test_complete_workflow_$$"
REMOTE_DIR="$BASE_DIR/remote.git"
CLONE1_DIR="$BASE_DIR/clone1"
CLONE2_DIR="$BASE_DIR/clone2"

rm -rf "$BASE_DIR"
mkdir -p "$BASE_DIR"

echo "Setup:"
echo "  Remote: $REMOTE_DIR"
echo "  Clone1: $CLONE1_DIR (user's working copy)"
echo "  Clone2: $CLONE2_DIR (system/server)"
echo

echo "=========================================="
echo "Phase 1: Initial Setup with WRONG encoding"
echo "=========================================="
echo

echo "Step 1: Create bare remote repository"
cd "$BASE_DIR"
git init --bare remote.git
echo

echo "Step 2: Create initial clone with WRONG .gitattributes"
git clone remote.git clone1
cd "$CLONE1_DIR"
git config user.name "Test User"
git config user.email "test@test.com"
echo

cat > .gitattributes << 'EOF'
* zos-working-tree-encoding=iso8859-1
*.yml zos-working-tree-encoding=ibm-1047 git-encoding=utf-8
EOF

cat > config.yml << 'EOF'
application:
  name: "MyApp"
  version: "1.0"
  encoding: "This should be IBM-1047"
EOF

# Manually set IBM-1047 tag
chtag -tc IBM-1047 config.yml

git add .
git commit -m "Initial commit with wrong yml encoding"
git push origin master
echo

echo "Initial state in clone1:"
chtag -p config.yml
TAG_PHASE1=$(chtag -p config.yml 2>&1 | awk '{print $2}')
echo "  Tag: $TAG_PHASE1"
echo

echo "=========================================="
echo "Phase 2: System pulls the repo"
echo "=========================================="
echo

echo "Step 3: Clone to 'system' (clone2)"
cd "$BASE_DIR"
git clone remote.git clone2
cd "$CLONE2_DIR"
git config user.name "System"
git config user.email "system@test.com"
echo

echo "File on system:"
chtag -p config.yml
TAG_SYSTEM_INITIAL=$(chtag -p config.yml 2>&1 | awk '{print $2}')
echo "  Tag: $TAG_SYSTEM_INITIAL"
echo "  ℹ️  This demonstrates the initial state"
echo

echo "=========================================="
echo "Phase 3: User discovers mistake and fixes it"
echo "=========================================="
echo

echo "Step 4: User changes .gitattributes in clone1"
cd "$CLONE1_DIR"

cat > .gitattributes << 'EOF'
* zos-working-tree-encoding=iso8859-1
*.yml zos-working-tree-encoding=ISO8859-1 git-encoding=utf-8
EOF

git add .gitattributes
git commit -m "Fix: Change yml encoding to ISO8859-1"
git push origin master
echo

echo "Step 5: Check file in clone1 - tag should NOT auto-change"
chtag -p config.yml
TAG_AFTER_FIX=$(chtag -p config.yml 2>&1 | awk '{print $2}')
echo "  Tag: $TAG_AFTER_FIX"
if [ "$TAG_AFTER_FIX" = "$TAG_PHASE1" ]; then
    echo "  ✅ Expected - tag unchanged"
else
    echo "  ⚠️ Tag changed unexpectedly"
fi
echo

echo "=========================================="
echo "Phase 4: User attempts fix - delete file"
echo "=========================================="
echo

echo "Step 6: User deletes config.yml and pushes"
cd "$CLONE1_DIR"
git rm -f config.yml
git commit -m "Delete config.yml"
git push origin master
echo "  ✅ File deleted and pushed"
echo

echo "Step 7: System pulls the deletion"
cd "$CLONE2_DIR"
git pull origin master
echo "  ✅ System pulled - file deleted"
echo

echo "=========================================="
echo "Phase 5: User creates new test file"
echo "=========================================="
echo

echo "Step 8: User creates test.yml (new file)"
cd "$CLONE1_DIR"

cat > test.yml << 'EOF'
test:
  name: "TestFile"
  purpose: "Verify new files work"
EOF

git add test.yml
git commit -m "Add test.yml"
git push origin master
echo

echo "Test file in clone1:"
chtag -p test.yml
TAG_TEST=$(chtag -p test.yml 2>&1 | awk '{print $2}')
echo "  Tag: $TAG_TEST (should be ISO8859-1)"
echo

echo "Step 9: System pulls test.yml"
cd "$CLONE2_DIR"
git pull origin master
echo

echo "Test file on system:"
chtag -p test.yml
TAG_TEST_SYSTEM=$(chtag -p test.yml 2>&1 | awk '{print $2}')
echo "  Tag: $TAG_TEST_SYSTEM (should be ISO8859-1)"
echo

echo "=========================================="
echo "Phase 6: THE BUG - Recreate original file"
echo "=========================================="
echo

echo "Step 10: User recreates config.yml with SAME NAME"
cd "$CLONE1_DIR"

cat > config.yml << 'EOF'
application:
  name: "MyApp"
  version: "1.0"
  encoding: "This should NOW be ISO8859-1"
EOF

git add config.yml
git commit -m "Recreate config.yml"
git push origin master
echo

echo "Recreated file in clone1:"
chtag -p config.yml
TAG_RECREATED_USER=$(chtag -p config.yml 2>&1 | awk '{print $2}')
echo "  Tag: $TAG_RECREATED_USER"
echo

echo "Step 11: System pulls the recreated file - THE CRITICAL TEST"
cd "$CLONE2_DIR"
git pull origin master
echo

echo "Recreated file on system:"
chtag -p config.yml
TAG_RECREATED_SYSTEM=$(chtag -p config.yml 2>&1 | awk '{print $2}')
echo "  Tag: $TAG_RECREATED_SYSTEM"
echo

echo "=========================================="
echo "FINAL RESULTS"
echo "=========================================="
echo
echo "Timeline of config.yml tags:"
echo "  Phase 1 - Initial (clone1):     $TAG_PHASE1"
echo "  Phase 2 - Initial (system):     $TAG_SYSTEM_INITIAL"
echo "  Phase 3 - After .gitattributes: $TAG_AFTER_FIX"
echo "  Phase 5 - test.yml (new file):  $TAG_TEST"
echo "  Phase 6 - Recreated (clone1):   $TAG_RECREATED_USER"
echo "  Phase 6 - Recreated (system):   $TAG_RECREATED_SYSTEM"
echo
echo "Critical comparison:"
echo "  New file (test.yml) on system:       $TAG_TEST_SYSTEM"
echo "  Recreated file (config.yml) on system: $TAG_RECREATED_SYSTEM"
echo

ISSUE_EXISTS=false

if [ "$TAG_RECREATED_SYSTEM" = "IBM-1047" ]; then
    echo "❌❌❌ ISSUE EXISTS ON SYSTEM! ❌❌❌"
    echo "The recreated file on system has OLD encoding (IBM-1047)"
    echo "Expected: ISO8859-1"
    ISSUE_EXISTS=true
elif [ "$TAG_RECREATED_SYSTEM" != "ISO8859-1" ]; then
    echo "⚠️ UNEXPECTED TAG: $TAG_RECREATED_SYSTEM"
    echo "Expected: ISO8859-1"
    ISSUE_EXISTS=true
fi

if [ "$TAG_RECREATED_USER" = "IBM-1047" ]; then
    echo "❌ Issue also exists in user's clone"
    ISSUE_EXISTS=true
elif [ "$TAG_RECREATED_USER" != "ISO8859-1" ]; then
    echo "⚠️ Unexpected tag in user's clone: $TAG_RECREATED_USER"
    ISSUE_EXISTS=true
fi

if [ "$ISSUE_EXISTS" = false ]; then
    echo "✅✅✅ ISSUE IS FIXED! ✅✅✅"
    echo
    echo "Both locations have correct encoding:"
    echo "  - User's clone:  $TAG_RECREATED_USER ✅"
    echo "  - System clone:  $TAG_RECREATED_SYSTEM ✅"
    echo
    echo "The recreated file correctly uses the new .gitattributes encoding"
    echo "This matches the expected behavior after the fix"
fi

echo
echo "=========================================="
echo "Verification"
echo "=========================================="
echo

echo "Git attributes (both clones should match):"
echo
echo "Clone1:"
cd "$CLONE1_DIR"
git check-attr -a config.yml test.yml
echo
echo "Clone2 (system):"
cd "$CLONE2_DIR"
git check-attr -a config.yml test.yml
echo

echo "Git status (both should be clean):"
echo "Clone1:"
cd "$CLONE1_DIR"
git status --short
echo "Clone2:"
cd "$CLONE2_DIR"
git status --short
echo

echo "=========================================="
echo "Summary"
echo "=========================================="
echo
if [ "$ISSUE_EXISTS" = false ]; then
    echo "✅ The Nov 2025 issue is FIXED in this Git version"
    echo "✅ Files recreated with same name get correct encoding"
    echo "✅ Both local and remote clones behave correctly"
else
    echo "❌ The Nov 2025 issue STILL EXISTS"
    echo "❌ Files recreated with same name keep old encoding"
    echo
    echo "WORKAROUNDS:"
    echo "  1. After changing .gitattributes:"
    echo "     git checkout -- config.yml"
    echo "  2. Or manually retag:"
    echo "     chtag -tc ISO8859-1 config.yml"
    echo "  3. Or clear cache:"
    echo "     git rm --cached config.yml && git add config.yml"
fi

echo
echo "Test directories:"
echo "  Base:   $BASE_DIR"
echo "  Clone1: $CLONE1_DIR"
echo "  Clone2: $CLONE2_DIR"
echo
echo "To inspect: cd $CLONE1_DIR or cd $CLONE2_DIR"
echo "To cleanup: rm -rf $BASE_DIR"
