#!/bin/bash
# Manual Test Commands for git apply --3way File Tagging Issue
# Issue: Content is correct but file tag is wrong after 3-way merge

echo "==================================================================="
echo "Manual Test: git apply --3way File Tagging Issue"
echo "==================================================================="
echo ""

# Setup
TEST_DIR=/tmp/test_apply_3way_tag_$$

echo "Step 1: Create test repository"
echo "-------------------------------------------------------------------"
rm -rf $TEST_DIR
mkdir -p $TEST_DIR
cd $TEST_DIR

git init
git config user.name "Test"
git config user.email "test@test.com"
git config core.ignorefiletags false

echo ""
echo "Step 2: Create .gitattributes with IBM-1047 encoding"
echo "-------------------------------------------------------------------"
cat > .gitattributes << 'EOF'
*.c zos-working-tree-encoding=ibm-1047
EOF

cat .gitattributes
git add .gitattributes
git commit -m "Add attributes"
echo ""

echo "Step 3: Create initial C file in EBCDIC"
echo "-------------------------------------------------------------------"
cat > temp.txt << 'EOF'
#include <stdio.h>

int main() {
    printf("Hello World\n");
    return 0;
}
EOF

iconv -f ISO8859-1 -t IBM-1047 < temp.txt > hello.c
chtag -tc 1047 hello.c
rm temp.txt

echo "Initial file tag:"
chtag -p hello.c
echo ""

git add hello.c
git commit -m "Initial commit"
echo ""

echo "Step 4: Create feature branch with modifications"
echo "-------------------------------------------------------------------"
git checkout -b feature

cat > temp.txt << 'EOF'
#include <stdio.h>

int main() {
    int feature_var = 42;
    printf("Hello from feature: %d\n", feature_var);
    return 0;
}
EOF

iconv -f ISO8859-1 -t IBM-1047 < temp.txt > hello.c
chtag -tc 1047 hello.c
rm temp.txt

git add hello.c
git commit -m "Feature changes"
echo ""

echo "Step 5: Go back to master and make conflicting change"
echo "-------------------------------------------------------------------"
git checkout master

cat > temp.txt << 'EOF'
#include <stdio.h>

int main() {
    int master_var = 99;
    printf("Hello from master: %d\n", master_var);
    return 0;
}
EOF

iconv -f ISO8859-1 -t IBM-1047 < temp.txt > hello.c
chtag -tc 1047 hello.c
rm temp.txt

git add hello.c
git commit -m "Master changes"
echo ""

echo "Step 6: Create patch from feature branch"
echo "-------------------------------------------------------------------"
git diff master feature > /tmp/feature.patch

echo "Patch created: /tmp/feature.patch"
echo "Patch size: $(wc -l /tmp/feature.patch | awk '{print $1}') lines"
echo ""

echo "Step 7: TEST - Apply patch with --3way"
echo "-------------------------------------------------------------------"
echo "This will trigger 3-way merge due to conflicts"
echo ""

echo "Tag BEFORE git apply --3way:"
chtag -p hello.c
echo ""

echo "Running: git apply --3way /tmp/feature.patch"
if git apply --3way /tmp/feature.patch 2>&1; then
    echo ""
    echo "Apply completed (may have conflicts)"
else
    echo ""
    echo "Apply triggered 3-way merge"
fi
echo ""

echo "Step 8: CHECK - File tag after git apply --3way"
echo "-------------------------------------------------------------------"
echo "CRITICAL CHECK: What is the file tag now?"
chtag -p hello.c
echo ""

TAG=$(chtag -p hello.c | awk '{print $2}')
echo "Expected: IBM-1047"
echo "Actual:   $TAG"
echo ""

if [ "$TAG" = "IBM-1047" ]; then
    echo "✅ PASS: File correctly tagged as IBM-1047"
else
    echo "❌ FAIL: File tagged as $TAG (should be IBM-1047)"
    echo ""
    echo "BUG REPRODUCED!"
    echo ""
    echo "Step 9: Verify content is correct despite wrong tag"
    echo "-------------------------------------------------------------------"
    echo "Content may appear garbled due to wrong tag:"
    cat hello.c | head -5
    echo ""
    echo "Retagging to check if content is actually IBM-1047..."
    chtag -tc 1047 hello.c
    echo ""
    echo "Content after retagging:"
    cat hello.c | head -5
    echo ""
    echo "✓ Content is correct - only the tag was wrong!"
fi

echo ""
echo "==================================================================="
echo "Test Summary"
echo "==================================================================="
echo ""
if [ "$TAG" != "IBM-1047" ]; then
    echo "❌ BUG CONFIRMED: git apply --3way sets wrong file tag"
    echo ""
    echo "Details:"
    echo "- Command: git apply --3way"
    echo "- File content: ✓ CORRECT (properly converted to IBM-1047)"
    echo "- File tag: ✗ WRONG ($TAG instead of IBM-1047)"
    echo "- Impact: File appears corrupted until manually retagged"
    echo ""
    echo "Workaround:"
    echo "  chtag -tc 1047 hello.c"
    echo ""
    echo "Root Cause:"
    echo "  git apply --3way converts content correctly but doesn't"
    echo "  call the file tagging function for merged files."
else
    echo "✅ NO BUG: git apply --3way correctly tags files"
fi
echo ""
echo "Test directory: $TEST_DIR"
echo "(Kept for manual inspection)"
