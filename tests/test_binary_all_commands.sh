#!/usr/bin/env bash
# ==============================================================================
# Survey: Binary file handling across all Git commands
# ==============================================================================
# This test ensures that binary files with wildcard encoding present
# are correctly tagged as binary (not encoding) across all Git operations.
#
# TAP format output
# ==============================================================================
set +e  # Don't exit on errors

# Check if running on z/OS
if [ "$(uname)" != "OS/390" ]; then
    echo "1..0 # SKIP Not running on z/OS"
    exit 0
fi

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

echo "TAP version 13"
echo "1..10"

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

cd "$TEST_ROOT"

# ==============================================================================
# Test 1: git checkout with binary
# ==============================================================================
mkdir t1 && cd t1
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "T" && $GIT_BIN config user.email "t@t.com"
$GIT_BIN config core.ignorefiletags false

cat > .gitattributes << 'EOF'
* text working-tree-encoding=UTF-8
.gitattributes working-tree-encoding=ISO8859-1
*.png binary -working-tree-encoding
EOF

echo -e "\x89PNG\x0D\x0A\x1A\x0A" > image.png
$GIT_BIN add .gitattributes image.png 2>/dev/null
$GIT_BIN commit -q -m "test" 2>/dev/null
rm image.png
$GIT_BIN checkout HEAD image.png 2>/dev/null

TAG=$(chtag -p image.png 2>/dev/null | awk '{print $1, $2}')
if echo "$TAG" | grep -q "b binary"; then
    tap_result "ok" "git checkout: binary file"
else
    tap_result "not ok" "git checkout: binary file" "got: $TAG"
fi
cd ..

# ==============================================================================
# Test 2: git merge with binary
# ==============================================================================
mkdir t2 && cd t2
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "T" && $GIT_BIN config user.email "t@t.com"
$GIT_BIN config core.ignorefiletags false

cat > .gitattributes << 'EOF'
* text working-tree-encoding=IBM-1047
.gitattributes working-tree-encoding=ISO8859-1
*.dll binary -working-tree-encoding
EOF

echo -e "MZ\x90\x00" > lib.dll
$GIT_BIN add .gitattributes lib.dll 2>/dev/null
$GIT_BIN commit -q -m "master" 2>/dev/null

$GIT_BIN checkout -b feature -q 2>/dev/null
echo -e "MZ\x90\x01" > lib.dll
$GIT_BIN add lib.dll 2>/dev/null
$GIT_BIN commit -q -m "feature" 2>/dev/null

$GIT_BIN checkout master -q 2>/dev/null
$GIT_BIN merge feature -q 2>/dev/null || true

TAG=$(chtag -p lib.dll 2>/dev/null | awk '{print $1, $2}')
if echo "$TAG" | grep -q "b binary"; then
    tap_result "ok" "git merge: binary file"
else
    tap_result "not ok" "git merge: binary file" "got: $TAG"
fi
cd ..

# ==============================================================================
# Test 3: git stash with binary
# ==============================================================================
mkdir t3 && cd t3
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "T" && $GIT_BIN config user.email "t@t.com"
$GIT_BIN config core.ignorefiletags false

cat > .gitattributes << 'EOF'
* text working-tree-encoding=ISO8859-1
.gitattributes working-tree-encoding=ISO8859-1
*.bin binary -working-tree-encoding
EOF

echo -e "\x00\x01\x02\x03" > data.bin
$GIT_BIN add .gitattributes data.bin 2>/dev/null
$GIT_BIN commit -q -m "test" 2>/dev/null

echo -e "\x04\x05\x06\x07" > data.bin
$GIT_BIN stash -q 2>/dev/null
$GIT_BIN stash apply -q 2>/dev/null

TAG=$(chtag -p data.bin 2>/dev/null | awk '{print $1, $2}')
if echo "$TAG" | grep -q "b binary"; then
    tap_result "ok" "git stash apply: binary file"
else
    tap_result "not ok" "git stash apply: binary file" "got: $TAG"
fi
cd ..

# ==============================================================================
# Test 4: git clone with binary
# ==============================================================================
mkdir t4 && cd t4
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "T" && $GIT_BIN config user.email "t@t.com"
$GIT_BIN config core.ignorefiletags false

cat > .gitattributes << 'EOF'
* text working-tree-encoding=UTF-8
.gitattributes working-tree-encoding=ISO8859-1
*.so binary -working-tree-encoding
EOF

echo -e "\x7FELF" > libtest.so
$GIT_BIN add .gitattributes libtest.so 2>/dev/null
$GIT_BIN commit -q -m "test" 2>/dev/null

cd ..
$GIT_BIN clone -q t4 t4_clone 2>/dev/null
cd t4_clone

TAG=$(chtag -p libtest.so 2>/dev/null | awk '{print $1, $2}')
if echo "$TAG" | grep -q "b binary"; then
    tap_result "ok" "git clone: binary file"
else
    tap_result "not ok" "git clone: binary file" "got: $TAG"
fi
cd ..

# ==============================================================================
# Test 5: git worktree with binary
# ==============================================================================
mkdir t5 && cd t5
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "T" && $GIT_BIN config user.email "t@t.com"
$GIT_BIN config core.ignorefiletags false

cat > .gitattributes << 'EOF'
* text working-tree-encoding=IBM-1047
.gitattributes working-tree-encoding=ISO8859-1
*.exe binary -working-tree-encoding
EOF

echo -e "MZ" > program.exe
$GIT_BIN add .gitattributes program.exe 2>/dev/null
$GIT_BIN commit -q -m "test" 2>/dev/null

$GIT_BIN worktree add -q ../t5_worktree HEAD 2>/dev/null
cd ../t5_worktree

TAG=$(chtag -p program.exe 2>/dev/null | awk '{print $1, $2}')
if echo "$TAG" | grep -q "b binary"; then
    tap_result "ok" "git worktree add: binary file"
else
    tap_result "not ok" "git worktree add: binary file" "got: $TAG"
fi
cd ..

# ==============================================================================
# Test 6: git pull with binary
# ==============================================================================
mkdir t6_remote && cd t6_remote
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "T" && $GIT_BIN config user.email "t@t.com"
$GIT_BIN config core.ignorefiletags false

cat > .gitattributes << 'EOF'
* text working-tree-encoding=UTF-8
.gitattributes working-tree-encoding=ISO8859-1
*.jar binary -working-tree-encoding
EOF

echo -e "PK\x03\x04" > lib.jar
$GIT_BIN add .gitattributes lib.jar 2>/dev/null
$GIT_BIN commit -q -m "v1" 2>/dev/null

cd ..
$GIT_BIN clone -q t6_remote t6_local 2>/dev/null

cd t6_remote
echo -e "PK\x03\x05" > lib.jar
$GIT_BIN add lib.jar 2>/dev/null
$GIT_BIN commit -q -m "v2" 2>/dev/null

cd ../t6_local
$GIT_BIN pull -q 2>/dev/null

TAG=$(chtag -p lib.jar 2>/dev/null | awk '{print $1, $2}')
if echo "$TAG" | grep -q "b binary"; then
    tap_result "ok" "git pull: binary file"
else
    tap_result "not ok" "git pull: binary file" "got: $TAG"
fi
cd ..

# ==============================================================================
# Test 7: git rebase with binary
# ==============================================================================
mkdir t7 && cd t7
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "T" && $GIT_BIN config user.email "t@t.com"
$GIT_BIN config core.ignorefiletags false

cat > .gitattributes << 'EOF'
* text working-tree-encoding=ISO8859-1
.gitattributes working-tree-encoding=ISO8859-1
*.o binary -working-tree-encoding
EOF

echo -e "\x7FELF" > obj.o
chtag -b obj.o 2>/dev/null
$GIT_BIN add .gitattributes obj.o 2>/dev/null
$GIT_BIN commit -q -m "master" 2>/dev/null

$GIT_BIN checkout -b feature -q 2>/dev/null
echo -e "\x7FELG" > obj.o
chtag -b obj.o 2>/dev/null
$GIT_BIN add obj.o 2>/dev/null
$GIT_BIN commit -q -m "feature" 2>/dev/null

$GIT_BIN rebase master -q 2>/dev/null || true

TAG=$(chtag -p obj.o 2>/dev/null | awk '{print $1, $2}')
if echo "$TAG" | grep -q "b binary"; then
    tap_result "ok" "git rebase: binary file"
else
    tap_result "not ok" "git rebase: binary file" "got: $TAG"
fi
cd ..

# ==============================================================================
# Test 8: git am with binary
# ==============================================================================
mkdir t8 && cd t8
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "T" && $GIT_BIN config user.email "t@t.com"
$GIT_BIN config core.ignorefiletags false

cat > .gitattributes << 'EOF'
* text working-tree-encoding=IBM-1047
.gitattributes working-tree-encoding=ISO8859-1
*.dat binary -working-tree-encoding
EOF

echo -e "\xFF\xFE" > data.dat
$GIT_BIN add .gitattributes data.dat 2>/dev/null
$GIT_BIN commit -q -m "v1" 2>/dev/null

echo -e "\xFF\xFF" > data.dat
$GIT_BIN add data.dat 2>/dev/null
$GIT_BIN commit -q -m "v2" 2>/dev/null

$GIT_BIN format-patch -1 HEAD -o /tmp 2>/dev/null
$GIT_BIN reset --hard HEAD~1 -q 2>/dev/null
$GIT_BIN am /tmp/0001-*.patch -q 2>/dev/null || true

TAG=$(chtag -p data.dat 2>/dev/null | awk '{print $1, $2}')
if echo "$TAG" | grep -q "b binary"; then
    tap_result "ok" "git am: binary file"
else
    tap_result "not ok" "git am: binary file" "got: $TAG"
fi
cd ..

# ==============================================================================
# Test 9: git restore with binary
# ==============================================================================
mkdir t9 && cd t9
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "T" && $GIT_BIN config user.email "t@t.com"
$GIT_BIN config core.ignorefiletags false

cat > .gitattributes << 'EOF'
* text working-tree-encoding=UTF-8
.gitattributes working-tree-encoding=ISO8859-1
*.pdf binary -working-tree-encoding
EOF

echo -e "%PDF" > doc.pdf
$GIT_BIN add .gitattributes doc.pdf 2>/dev/null
$GIT_BIN commit -q -m "test" 2>/dev/null

echo "modified" > doc.pdf
$GIT_BIN restore doc.pdf 2>/dev/null

TAG=$(chtag -p doc.pdf 2>/dev/null | awk '{print $1, $2}')
if echo "$TAG" | grep -q "b binary"; then
    tap_result "ok" "git restore: binary file"
else
    tap_result "not ok" "git restore: binary file" "got: $TAG"
fi
cd ..

# ==============================================================================
# Test 10: git diff --output with binary
# ==============================================================================
mkdir t10 && cd t10
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "T" && $GIT_BIN config user.email "t@t.com"
$GIT_BIN config core.ignorefiletags false

cat > .gitattributes << 'EOF'
* text working-tree-encoding=IBM-1047
.gitattributes working-tree-encoding=ISO8859-1
*.bin binary -working-tree-encoding
EOF

echo -e "\x00\x01" > file.bin
$GIT_BIN add .gitattributes file.bin 2>/dev/null
$GIT_BIN commit -q -m "test" 2>/dev/null

echo "text" > regular.txt
$GIT_BIN diff --output=/tmp/diff_output.txt 2>/dev/null

if [ -f /tmp/diff_output.txt ]; then
    TAG=$(chtag -p /tmp/diff_output.txt 2>/dev/null | awk '{print $2}')
    # diff output should NOT be binary (it's a text diff)
    if [ "$TAG" != "binary" ]; then
        tap_result "ok" "git diff --output: creates text file (not binary)"
    else
        tap_result "not ok" "git diff --output: creates text file (not binary)" "got: $TAG"
    fi
else
    tap_result "ok" "git diff --output: no output (expected)"
fi
cd ..

# Clean up
cd /
rm -rf "$TEST_ROOT"

exit $FAIL_COUNT
