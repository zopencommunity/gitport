#!/usr/bin/env bash
# ==============================================================================
# Test for git pull/checkout encoding tag bug with .gitattributes updates  
# Tests the fix in stable-patches/unpack-trees.c.patch
# ==============================================================================
set -e

# Find git binary
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -x "$REPO_ROOT/git/git" ]; then
    GIT_BIN="$REPO_ROOT/git/git"
else
    GIT_BIN="$(which git)"
fi

TEST_ROOT="$(pwd)/test_tmp_$$"
mkdir -p "$TEST_ROOT"
trap 'rm -rf "$TEST_ROOT"' EXIT

echo "========================================================================"
echo "  GIT ENCODING TAG BUG TEST (.gitattributes attribute cache)"
echo "========================================================================"
echo "Git binary: $("$GIT_BIN" --version) ($GIT_BIN)"
echo "Test root:  $TEST_ROOT"

cd "$TEST_ROOT"

# ==============================================================================
# Test: Checkout when .gitattributes changes encoding
# ==============================================================================
echo ""
echo "Test 1: Checkout between commits with different .gitattributes encodings"
echo "--------------------------------------------------------------------------"

mkdir repo
cd repo
"$GIT_BIN" init -q
"$GIT_BIN" config user.name "Test"
"$GIT_BIN" config user.email "test@test.com"

# Commit 1: ISO-8859-1 encoding
cat << 'ATTR' > .gitattributes
*.txt zos-working-tree-encoding=ISO8859-1
ATTR

echo "Content v1" > file.txt
"$GIT_BIN" add .
"$GIT_BIN" commit -m "commit1: ISO8859-1" -q

COMMIT1=$("$GIT_BIN" rev-parse HEAD)

# Commit 2: Change encoding to IBM-1047 in .gitattributes
cat << 'ATTR' > .gitattributes
*.txt zos-working-tree-encoding=IBM-1047
ATTR

echo "Content v2" > file.txt
"$GIT_BIN" add .
"$GIT_BIN" commit -m "commit2: IBM-1047" -q

COMMIT2=$("$GIT_BIN" rev-parse HEAD)

# Now test: checkout commit1, then checkout commit2
# The file should get the correct encoding tag each time

"$GIT_BIN" checkout "$COMMIT1" -q 2>&1 | grep -v "detached HEAD" || true
TAG1=$(chtag -p file.txt | awk '{print $2}')
echo "After checkout commit1: tag=$TAG1"

if [ "$TAG1" != "ISO8859-1" ]; then
    echo "✗ FAIL: Expected ISO8859-1, got $TAG1"
    exit 1
fi

"$GIT_BIN" checkout "$COMMIT2" -q 2>&1 | grep -v "detached HEAD" || true  
TAG2=$(chtag -p file.txt | awk '{print $2}')
echo "After checkout commit2: tag=$TAG2"

if [ "$TAG2" != "IBM-1047" ]; then
    echo "✗ FAIL: Expected IBM-1047, got $TAG2"
    echo "This indicates the attribute cache was NOT invalidated when .gitattributes changed"
    exit 1
fi

echo "✓ PASS: File correctly retagged when checking out commit with different .gitattributes"

# ==============================================================================
# Test 2: Multiple files with attribute changes
# ==============================================================================
cd "$TEST_ROOT"
echo ""
echo "Test 2: Multiple files with encoding changes in .gitattributes"
echo "----------------------------------------------------------------"

mkdir repo2
cd repo2
"$GIT_BIN" init -q
"$GIT_BIN" config user.name "Test"
"$GIT_BIN" config user.email "test@test.com"

# Commit 1: Mixed encodings
cat << 'ATTR' > .gitattributes
file1.txt zos-working-tree-encoding=ISO8859-1
file2.txt zos-working-tree-encoding=ISO8859-1
file3.txt zos-working-tree-encoding=IBM-1047
ATTR

echo "File 1" > file1.txt
echo "File 2" > file2.txt
echo "File 3" > file3.txt
"$GIT_BIN" add .
"$GIT_BIN" commit -m "commit1: mixed encodings" -q

C1=$("$GIT_BIN" rev-parse HEAD)

# Commit 2: All IBM-1047
cat << 'ATTR' > .gitattributes
*.txt zos-working-tree-encoding=IBM-1047
ATTR

echo "File 1 v2" > file1.txt
echo "File 2 v2" > file2.txt
echo "File 3 v2" > file3.txt
"$GIT_BIN" add .
"$GIT_BIN" commit -m "commit2: all IBM-1047" -q

C2=$("$GIT_BIN" rev-parse HEAD)

# Checkout commit1
"$GIT_BIN" checkout "$C1" -q 2>&1 | grep -v "detached HEAD" || true

T1=$(chtag -p file1.txt | awk '{print $2}')
T2=$(chtag -p file2.txt | awk '{print $2}')
T3=$(chtag -p file3.txt | awk '{print $2}')

echo "After checkout commit1: file1=$T1, file2=$T2, file3=$T3"

[ "$T1" = "ISO8859-1" ] || { echo "✗ FAIL: file1 wrong tag"; exit 1; }
[ "$T2" = "ISO8859-1" ] || { echo "✗ FAIL: file2 wrong tag"; exit 1; }
[ "$T3" = "IBM-1047" ] || { echo "✗ FAIL: file3 wrong tag"; exit 1; }

# Checkout commit2
"$GIT_BIN" checkout "$C2" -q 2>&1 | grep -v "detached HEAD" || true

T1=$(chtag -p file1.txt | awk '{print $2}')
T2=$(chtag -p file2.txt | awk '{print $2}')
T3=$(chtag -p file3.txt | awk '{print $2}')

echo "After checkout commit2: file1=$T1, file2=$T2, file3=$T3"

[ "$T1" = "IBM-1047" ] || { echo "✗ FAIL: file1 not retagged"; exit 1; }
[ "$T2" = "IBM-1047" ] || { echo "✗ FAIL: file2 not retagged"; exit 1; }
[ "$T3" = "IBM-1047" ] || { echo "✗ FAIL: file3 tag wrong"; exit 1; }

echo "✓ PASS: All files correctly retagged"

# ==============================================================================
# Test 3: Subdirectory .gitattributes
# ==============================================================================
cd "$TEST_ROOT"
echo ""
echo "Test 3: Subdirectory .gitattributes addition"
echo "----------------------------------------------"

mkdir repo3
cd repo3
"$GIT_BIN" init -q
"$GIT_BIN" config user.name "Test"
"$GIT_BIN" config user.email "test@test.com"

# Commit 1: Root .gitattributes only
cat << 'ATTR' > .gitattributes
*.txt zos-working-tree-encoding=ISO8859-1
ATTR

mkdir subdir
echo "Subdir file" > subdir/data.txt
"$GIT_BIN" add .
"$GIT_BIN" commit -m "commit1: root attr" -q

C1=$("$GIT_BIN" rev-parse HEAD)

# Commit 2: Add subdirectory .gitattributes
cat << 'ATTR' > subdir/.gitattributes
*.txt zos-working-tree-encoding=IBM-1047
ATTR

echo "Subdir file v2" > subdir/data.txt
"$GIT_BIN" add .
"$GIT_BIN" commit -m "commit2: subdir attr" -q

C2=$("$GIT_BIN" rev-parse HEAD)

# Test checkout
"$GIT_BIN" checkout "$C1" -q 2>&1 | grep -v "detached HEAD" || true
T1=$(chtag -p subdir/data.txt | awk '{print $2}')
echo "After checkout commit1: subdir/data.txt=$T1"
[ "$T1" = "ISO8859-1" ] || { echo "✗ FAIL: subdir file wrong tag at C1"; exit 1; }

"$GIT_BIN" checkout "$C2" -q 2>&1 | grep -v "detached HEAD" || true
T2=$(chtag -p subdir/data.txt | awk '{print $2}')
echo "After checkout commit2: subdir/data.txt=$T2"
[ "$T2" = "IBM-1047" ] || { echo "✗ FAIL: subdir file not retagged at C2"; exit 1; }

echo "✓ PASS: Subdirectory .gitattributes correctly applied"

# Cleanup
cd /
rm -rf "$TEST_ROOT"

echo ""
echo "========================================================================"
echo "  ALL TESTS PASSED: Attribute cache invalidation working correctly!"
echo "========================================================================"
echo ""
echo "The fix in stable-patches/unpack-trees.c.patch ensures that when"
echo ".gitattributes is updated during checkout/pull, the attribute cache"
echo "is invalidated so that files get the correct encoding tags."
