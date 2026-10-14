#!/bin/bash
# Manual Test Commands for git stash push <file> Issue
# Issue: File is restored with wrong encoding tag after git stash push <file>
# Expected: IBM-1047, Actual: ISO8859-1

echo "==================================================================="
echo "Manual Test: git stash push <file> Encoding Issue"
echo "==================================================================="
echo ""

# Setup
GIT_BIN=/home/haritha/code/bazel-7.2.0/git_255_iconv_translit_3waymerge/gitport/git/git
TEST_DIR=/tmp/test_stash_push_file_$$

echo "Step 1: Create test repository"
echo "-------------------------------------------------------------------"
rm -rf $TEST_DIR
mkdir -p $TEST_DIR
cd $TEST_DIR

$GIT_BIN init
$GIT_BIN config user.name "Test"
$GIT_BIN config user.email "test@test.com"
$GIT_BIN config core.ignorefiletags false

echo ""
echo "Step 2: Create .gitattributes with IBM-1047 encoding"
echo "-------------------------------------------------------------------"
mkdir -p cobfe/zosGen/src
cat > .gitattributes << 'EOF'
cobfe/zosGen/src/* zos-working-tree-encoding=ibm-1047
EOF

cat .gitattributes
echo ""

echo "Step 3: Create an EBCDIC file (simulating COBOL source)"
echo "-------------------------------------------------------------------"
# Create file with some COBOL-like content
cat > cobfe/zosGen/src/igyvcntl.plx << 'EOF'
       IDENTIFICATION DIVISION.
       PROGRAM-ID. TESTPROG.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-COUNT    PIC 9(5) VALUE 0.
       PROCEDURE DIVISION.
           DISPLAY "Hello World".
           STOP RUN.
EOF

# Convert to EBCDIC and tag
echo "Original file (ASCII):"
cat cobfe/zosGen/src/igyvcntl.plx | head -3
echo ""

echo "Converting to IBM-1047 and tagging..."
iconv -f ISO8859-1 -t IBM-1047 < cobfe/zosGen/src/igyvcntl.plx > /tmp/ebcdic_temp.plx
mv /tmp/ebcdic_temp.plx cobfe/zosGen/src/igyvcntl.plx
chtag -tc 1047 cobfe/zosGen/src/igyvcntl.plx

echo "File tag:"
chtag -p cobfe/zosGen/src/igyvcntl.plx
echo ""

echo "Step 4: Add and commit the file"
echo "-------------------------------------------------------------------"
$GIT_BIN add .gitattributes cobfe/zosGen/src/igyvcntl.plx
$GIT_BIN commit -m "Initial commit with COBOL file"
echo ""

echo "Step 5: Modify the file"
echo "-------------------------------------------------------------------"
# Modify in EBCDIC
echo "       01  WS-MODIFIED PIC X(10) VALUE 'CHANGED'." | iconv -f ISO8859-1 -t IBM-1047 >> cobfe/zosGen/src/igyvcntl.plx
chtag -tc 1047 cobfe/zosGen/src/igyvcntl.plx

echo "Modified file - tag before stash:"
chtag -p cobfe/zosGen/src/igyvcntl.plx
echo ""

echo "Git status:"
$GIT_BIN status --short
echo ""

echo "Step 6: TEST - git stash push <file>"
echo "-------------------------------------------------------------------"
echo "Running: git stash push cobfe/zosGen/src/igyvcntl.plx"
$GIT_BIN stash push cobfe/zosGen/src/igyvcntl.plx
echo ""

echo "Step 7: CHECK - File tag after stash"
echo "-------------------------------------------------------------------"
echo "CRITICAL CHECK: What is the file tag now?"
chtag -p cobfe/zosGen/src/igyvcntl.plx
echo ""

echo "Expected: t IBM-1047"
echo "Actual:   $(chtag -p cobfe/zosGen/src/igyvcntl.plx | awk '{print $1, $2}')"
echo ""

TAG=$(chtag -p cobfe/zosGen/src/igyvcntl.plx | awk '{print $2}')
if [ "$TAG" = "IBM-1047" ]; then
    echo "✅ PASS: File correctly tagged as IBM-1047"
else
    echo "❌ FAIL: File tagged as $TAG (should be IBM-1047)"
    echo ""
    echo "BUG REPRODUCED!"
    echo "File is readable after retagging:"
    echo "chtag -tc 1047 cobfe/zosGen/src/igyvcntl.plx"
fi
echo ""

echo "Step 8: Verify file content (may be garbled if wrong tag)"
echo "-------------------------------------------------------------------"
echo "First 3 lines of file:"
cat cobfe/zosGen/src/igyvcntl.plx 2>/dev/null | head -3 || echo "Cannot read (encoding issue)"
echo ""

echo "Step 9: Compare with git stash pop (should work correctly)"
echo "-------------------------------------------------------------------"
echo "Popping stash..."
$GIT_BIN stash pop
echo ""

echo "File tag after pop:"
chtag -p cobfe/zosGen/src/igyvcntl.plx
echo ""

TAG_AFTER_POP=$(chtag -p cobfe/zosGen/src/igyvcntl.plx | awk '{print $2}')
if [ "$TAG_AFTER_POP" = "IBM-1047" ]; then
    echo "✅ PASS: File correctly tagged as IBM-1047 after pop"
else
    echo "❌ FAIL: File tagged as $TAG_AFTER_POP after pop"
fi
echo ""

echo "==================================================================="
echo "Test Summary"
echo "==================================================================="
echo ""
if [ "$TAG" != "IBM-1047" ]; then
    echo "❌ BUG CONFIRMED: git stash push <file> tags file incorrectly"
    echo ""
    echo "Issue Details:"
    echo "- Command: git stash push cobfe/zosGen/src/igyvcntl.plx"
    echo "- Expected tag: IBM-1047"
    echo "- Actual tag: $TAG"
    echo "- File becomes unreadable due to wrong encoding tag"
    echo ""
    echo "Workaround:"
    echo "  chtag -tc 1047 cobfe/zosGen/src/igyvcntl.plx"
    echo ""
    echo "Note: 'git stash push' (without file) works correctly"
    echo "Note: 'git stash pop' restores tag correctly"
    EXIT_CODE=1
else
    echo "✅ NO BUG: git stash push <file> works correctly"
    EXIT_CODE=0
fi
echo ""

echo "Test directory: $TEST_DIR"
echo "(Directory will be kept for manual inspection)"
echo ""

exit $EXIT_CODE
