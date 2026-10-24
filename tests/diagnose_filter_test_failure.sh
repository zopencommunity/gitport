#!/bin/bash
# Diagnose why filter tests are failing

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║     Filter Test Failure Diagnosis                                             ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

echo "Step 1: Check Git binary"
echo "════════════════════════════════════════════════════════════════════════════════"
which git
git --version
echo ""

echo "Step 2: Verify the fix was applied"
echo "════════════════════════════════════════════════════════════════════════════════"
echo "Checking git/convert.c around line 1612..."
cd ../git 2>/dev/null || cd git 2>/dev/null || { echo "Cannot find git directory"; exit 1; }

# Check if #ifdef __MVS__ exists in convert_to_git_filter_fd
if grep -A 20 "convert_to_git_filter_fd" convert.c | grep -q "#ifdef __MVS__"; then
    echo "❌ FOUND: #ifdef __MVS__ block still exists!"
    echo ""
    echo "The block around convert_to_git_filter_fd:"
    grep -A 30 "convert_to_git_filter_fd" convert.c | head -35
    echo ""
    echo "PROBLEM: The fix was not applied!"
    echo "ACTION: Remove the #ifdef __MVS__ block (lines 1612-1626)"
else
    echo "✅ GOOD: No #ifdef __MVS__ found in convert_to_git_filter_fd"
    echo ""
    echo "The encode_to_git call:"
    grep -A 5 "convert_to_git_filter_fd" convert.c | grep -A 3 "encode_to_git"
fi

echo ""
echo "Step 3: Check if git was rebuilt"
echo "════════════════════════════════════════════════════════════════════════════════"
ls -l git 2>/dev/null || ls -l ../git/git 2>/dev/null
echo ""
BUILT_GIT=$(find . -name "git" -type f -executable | grep -v ".git/" | head -1)
if [ -n "$BUILT_GIT" ]; then
    echo "Found git binary: $BUILT_GIT"
    strings "$BUILT_GIT" | grep -i "skip encode_to_git" && echo "⚠️  OLD binary still has skip message" || echo "✓ No skip message found"
fi

echo ""
echo "Step 4: Run simple filter test manually"
echo "════════════════════════════════════════════════════════════════════════════════"

cd ..
TEST_DIR="/tmp/quick_filter_test_$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

git init -q
git config user.email "test@test.com"
git config user.name "Test"

# Create cat filter
cat > filter.sh << 'FILTER'
#!/bin/bash
cat
FILTER
chmod +x filter.sh

git config filter.test.clean "$(pwd)/filter.sh"
git config filter.test.required true

# Create .gitattributes
echo "*.txt filter=test working-tree-encoding=IBM-1047" > .gitattributes

# Create EBCDIC file
echo "Testing" > test_utf8.txt
iconv -f UTF-8 -t IBM-1047 test_utf8.txt > test.txt
chtag -tc IBM-1047 test.txt

echo "File content:"
od -A x -t x1 -N 8 test.txt

# Add to git
git add .gitattributes test.txt

# Check object
HASH=$(git ls-files -s test.txt | awk '{print $2}')
echo ""
echo "Git object content:"
git cat-file -p "$HASH" | od -A x -t x1 -N 8

BYTES=$(git cat-file -p "$HASH" | od -A n -t x1 -N 4 | tr -d ' \n')
echo ""
echo "First 4 bytes: $BYTES"

if echo "$BYTES" | grep -qi "^54657374"; then
    echo "✅ UTF-8 detected - FIX IS WORKING!"
elif echo "$BYTES" | grep -qi "^e385a2a3"; then
    echo "❌ EBCDIC detected - FIX NOT WORKING!"
else
    echo "⚠️  Unknown: $BYTES"
fi

cd /
rm -rf "$TEST_DIR"

