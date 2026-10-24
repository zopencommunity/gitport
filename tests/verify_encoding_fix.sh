#!/bin/bash
#
# Quick verification script for Nov 2025 GitHub issue
# Run this to verify if the encoding persistence issue is fixed on your system
#
# Usage: ./verify_encoding_fix.sh
#

echo "=========================================="
echo "Nov 2025 Issue Verification Script"
echo "Testing: File encoding persistence after .gitattributes change"
echo "=========================================="
echo

# Check Git version
GIT_VERSION=$(git --version)
echo "Git version: $GIT_VERSION"
echo

# Create temp test directory
TEST_DIR="/tmp/verify_encoding_fix_$$"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo "Creating test repository..."
git init -q
git config user.name "Test"
git config user.email "test@test.com"

# Step 1: Wrong encoding
cat > .gitattributes << 'EOF'
*.yml zos-working-tree-encoding=ibm-1047 git-encoding=utf-8
EOF

cat > test.yml << 'EOF'
name: test
value: 123
EOF

chtag -tc IBM-1047 test.yml 2>/dev/null
git add .
git commit -q -m "Initial with IBM-1047"

echo "1. Initial file tag:"
TAG1=$(chtag -p test.yml 2>&1 | awk '{print $2}')
echo "   $TAG1"

# Step 2: Fix encoding
cat > .gitattributes << 'EOF'
*.yml zos-working-tree-encoding=ISO8859-1 git-encoding=utf-8
EOF

git add .gitattributes
git commit -q -m "Fix encoding to ISO8859-1"

echo "2. After .gitattributes change:"
TAG2=$(chtag -p test.yml 2>&1 | awk '{print $2}')
echo "   $TAG2 (should stay same)"

# Step 3: Delete and recreate
git rm -f test.yml >/dev/null 2>&1
git commit -q -m "Delete"

cat > test.yml << 'EOF'
name: test
value: 123
EOF

git add test.yml
git commit -q -m "Recreate"

echo "3. Recreated file tag:"
TAG3=$(chtag -p test.yml 2>&1 | awk '{print $2}')
echo "   $TAG3"

# Verdict
echo
echo "=========================================="
echo "RESULT:"
echo "=========================================="
echo "Initial:   $TAG1"
echo "Recreated: $TAG3"
echo

if [ "$TAG3" = "ISO8859-1" ]; then
    echo "✅ PASS - Issue is FIXED on your system!"
    echo "   Recreated file correctly uses new encoding"
    RESULT=0
else
    echo "❌ FAIL - Issue still exists on your system"
    echo "   Expected: ISO8859-1"
    echo "   Got:      $TAG3"
    echo
    echo "   You need to upgrade Git or use workarounds:"
    echo "   - git checkout -- filename.yml"
    echo "   - chtag -tc ISO8859-1 filename.yml"
    RESULT=1
fi

# Cleanup
cd /
rm -rf "$TEST_DIR"

echo
echo "Test complete"
exit $RESULT
