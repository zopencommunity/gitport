#!/bin/bash
# Manual Test Commands for git rerere + cherry-pick Encoding Issue
# Issue: After cherry-pick with conflicts, rerere auto-resolves but files lose encoding tags

echo "==================================================================="
echo "Manual Test: git rerere + cherry-pick Encoding Issue"
echo "==================================================================="
echo ""

# Setup
GIT_BIN=/home/haritha/code/bazel-7.2.0/git_255_iconv_translit_3waymerge/gitport/git/git
TEST_DIR=/tmp/test_rerere_cherry_$$

echo "Step 1: Create test repository"
echo "-------------------------------------------------------------------"
rm -rf $TEST_DIR
mkdir -p $TEST_DIR
cd $TEST_DIR

$GIT_BIN init
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false
$GIT_BIN config rerere.enabled true

echo ""
echo "Step 2: Create .gitattributes with IBM-1047 encoding"
echo "-------------------------------------------------------------------"
cat > .gitattributes << 'EOF'
*.txt zos-working-tree-encoding=ibm-1047
EOF

cat .gitattributes
echo ""

echo "Step 3: Create initial EBCDIC file"
echo "-------------------------------------------------------------------"
# Create file
cat > temp.txt << 'EOF'
       IDENTIFICATION DIVISION.
       PROGRAM-ID. MAINPROG.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-COUNTER    PIC 9(5) VALUE 0.
       PROCEDURE DIVISION.
           DISPLAY "Version 1".
           STOP RUN.
EOF

# Convert to EBCDIC
iconv -f ISO8859-1 -t IBM-1047 < temp.txt > file.txt
chtag -tc 1047 file.txt
rm temp.txt

echo "Initial file tag:"
chtag -p file.txt
echo ""

$GIT_BIN add .gitattributes file.txt
$GIT_BIN commit -m "Initial commit"
echo ""

echo "Step 4: Create branch A with modification"
echo "-------------------------------------------------------------------"
$GIT_BIN checkout -b branch-a

cat > temp.txt << 'EOF'
       IDENTIFICATION DIVISION.
       PROGRAM-ID. MAINPROG.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-COUNTER    PIC 9(5) VALUE 0.
       01  WS-BRANCH-A   PIC X(10) VALUE 'BRANCH-A'.
       PROCEDURE DIVISION.
           DISPLAY "Version 1".
           STOP RUN.
EOF

iconv -f ISO8859-1 -t IBM-1047 < temp.txt > file.txt
chtag -tc 1047 file.txt
rm temp.txt

$GIT_BIN add file.txt
$GIT_BIN commit -m "Branch A changes"
echo ""

echo "Step 5: Go back to main and create conflicting change"
echo "-------------------------------------------------------------------"
$GIT_BIN checkout main

cat > temp.txt << 'EOF'
       IDENTIFICATION DIVISION.
       PROGRAM-ID. MAINPROG.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-COUNTER    PIC 9(5) VALUE 0.
       01  WS-MAIN       PIC X(10) VALUE 'MAIN-VER'.
       PROCEDURE DIVISION.
           DISPLAY "Version 1".
           STOP RUN.
EOF

iconv -f ISO8859-1 -t IBM-1047 < temp.txt > file.txt
chtag -tc 1047 file.txt
rm temp.txt

$GIT_BIN add file.txt
$GIT_BIN commit -m "Main changes (conflicts with branch-a)"
echo ""

echo "Step 6: Cherry-pick from branch-a (will conflict)"
echo "-------------------------------------------------------------------"
BRANCH_A_COMMIT=$($GIT_BIN rev-parse branch-a)
echo "Cherry-picking: $BRANCH_A_COMMIT"
echo ""

if ! $GIT_BIN cherry-pick branch-a 2>&1; then
    echo ""
    echo "Conflict occurred (expected)"
    echo ""
    
    # Show conflict markers
    echo "File content with conflict markers:"
    cat file.txt | head -20
    echo ""
    
    # Resolve the conflict
    echo "Step 7: Resolving conflict..."
    echo "-------------------------------------------------------------------"
    cat > temp.txt << 'EOF'
       IDENTIFICATION DIVISION.
       PROGRAM-ID. MAINPROG.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-COUNTER    PIC 9(5) VALUE 0.
       01  WS-MAIN       PIC X(10) VALUE 'MAIN-VER'.
       01  WS-BRANCH-A   PIC X(10) VALUE 'BRANCH-A'.
       PROCEDURE DIVISION.
           DISPLAY "Version 1".
           STOP RUN.
EOF

    iconv -f ISO8859-1 -t IBM-1047 < temp.txt > file.txt
    chtag -tc 1047 file.txt
    rm temp.txt
    
    $GIT_BIN add file.txt
    $GIT_BIN cherry-pick --continue -m "Resolved cherry-pick" 2>&1
    echo ""
    
    echo "Step 8: Check file tag after resolved cherry-pick"
    echo "-------------------------------------------------------------------"
    echo "File tag:"
    chtag -p file.txt
    echo ""
    
    TAG=$(chtag -p file.txt | awk '{print $2}')
    echo "Expected: IBM-1047"
    echo "Actual:   $TAG"
    echo ""
    
    if [ "$TAG" = "IBM-1047" ]; then
        echo "✅ PASS: File correctly tagged"
    else
        echo "❌ FAIL: File has WRONG tag!"
        echo ""
        echo "This is the first resolution - rerere recorded it."
    fi
else
    echo "No conflict occurred (unexpected)"
fi

echo ""
echo "Step 9: TEST RERERE - Undo and replay to trigger rerere"
echo "-------------------------------------------------------------------"
$GIT_BIN reset --hard HEAD~1
echo "Reset to before cherry-pick"
echo ""

echo "Step 10: Cherry-pick again (rerere should auto-resolve)"
echo "-------------------------------------------------------------------"
if ! $GIT_BIN cherry-pick branch-a 2>&1; then
    echo ""
    echo "Rerere should have auto-resolved..."
    $GIT_BIN rerere status
    echo ""
    
    # Check if rerere resolved it
    if $GIT_BIN diff --quiet; then
        echo "✓ Rerere auto-resolved the conflict"
    else
        echo "⚠ Rerere did not fully resolve"
    fi
    
    # Complete the cherry-pick
    $GIT_BIN add file.txt 2>&1
    $GIT_BIN cherry-pick --continue -m "Rerere resolved" 2>&1
fi

echo ""
echo "Step 11: CHECK - File tag after rerere resolution"
echo "-------------------------------------------------------------------"
echo "CRITICAL CHECK: What is the file tag now?"
chtag -p file.txt
echo ""

TAG_RERERE=$(chtag -p file.txt | awk '{print $2}')
echo "Expected: IBM-1047"
echo "Actual:   $TAG_RERERE"
echo ""

if [ "$TAG_RERERE" = "IBM-1047" ]; then
    echo "✅ PASS: Rerere preserved encoding tag"
else
    echo "❌ FAIL: Rerere did NOT preserve encoding tag!"
    echo ""
    echo "BUG REPRODUCED!"
    echo ""
    echo "File content may appear corrupted:"
    cat file.txt | head -5
    echo ""
    echo "Workaround: chtag -tc 1047 file.txt"
fi

echo ""
echo "==================================================================="
echo "Test Summary"
echo "==================================================================="
echo ""
if [ "$TAG_RERERE" != "IBM-1047" ]; then
    echo "❌ BUG CONFIRMED: git rerere + cherry-pick loses encoding tag"
    echo ""
    echo "Details:"
    echo "- Command: git cherry-pick (with conflicts)"
    echo "- Rerere: Enabled and auto-resolved"
    echo "- Expected tag: IBM-1047"
    echo "- Actual tag: $TAG_RERERE"
    echo "- File becomes unreadable due to wrong encoding tag"
else
    echo "✅ NO BUG: git rerere + cherry-pick works correctly"
fi
echo ""
echo "Test directory: $TEST_DIR"
echo "(Kept for manual inspection)"
