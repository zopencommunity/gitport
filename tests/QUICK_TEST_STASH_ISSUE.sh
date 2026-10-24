# Quick Manual Test Commands for git stash push <file> Issue
# Copy and paste these commands one by one

# 1. Setup test directory
cd /tmp
rm -rf test_stash_issue
mkdir test_stash_issue
cd test_stash_issue

# 2. Initialize git repo
git init
git config user.name "Test"
git config user.email "test@test.com"
git config core.ignorefiletags false

# 3. Create directory structure and .gitattributes
mkdir -p cobfe/zosGen/src
echo "cobfe/zosGen/src/* zos-working-tree-encoding=ibm-1047" > .gitattributes

# 4. Create a test COBOL file in EBCDIC
cat > /tmp/test_cobol.txt << 'EOF'
       IDENTIFICATION DIVISION.
       PROGRAM-ID. TESTPROG.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-COUNT    PIC 9(5) VALUE 0.
EOF

# Convert to EBCDIC and tag
iconv -f ISO8859-1 -t IBM-1047 < /tmp/test_cobol.txt > cobfe/zosGen/src/igyvcntl.plx
chtag -tc 1047 cobfe/zosGen/src/igyvcntl.plx

# 5. Check the tag (should be IBM-1047)
echo "Initial tag:"
chtag -p cobfe/zosGen/src/igyvcntl.plx

# 6. Commit the file
git add .gitattributes cobfe/zosGen/src/igyvcntl.plx
git commit -m "Add COBOL file"

# 7. Modify the file
echo "       01  WS-NEW    PIC X(10)." | iconv -f ISO8859-1 -t IBM-1047 >> cobfe/zosGen/src/igyvcntl.plx
chtag -tc 1047 cobfe/zosGen/src/igyvcntl.plx

# 8. Check status
git status

# 9. *** THE TEST *** - Stash the specific file
echo ""
echo "=== TESTING: git stash push <file> ==="
echo "Tag BEFORE stash:"
chtag -p cobfe/zosGen/src/igyvcntl.plx

git stash push cobfe/zosGen/src/igyvcntl.plx

echo "Tag AFTER stash:"
chtag -p cobfe/zosGen/src/igyvcntl.plx

# 10. Check the result
echo ""
echo "=== RESULT CHECK ==="
TAG=$(chtag -p cobfe/zosGen/src/igyvcntl.plx | awk '{print $2}')
if [ "$TAG" = "IBM-1047" ]; then
    echo "✅ PASS: Tag is correct (IBM-1047)"
else
    echo "❌ FAIL: Tag is WRONG ($TAG instead of IBM-1047)"
    echo ""
    echo "File content (may be garbled):"
    head -3 cobfe/zosGen/src/igyvcntl.plx
    echo ""
    echo "To fix: chtag -tc 1047 cobfe/zosGen/src/igyvcntl.plx"
fi

# 11. Compare with git stash pop
echo ""
echo "=== TESTING: git stash pop ==="
git stash pop
echo "Tag after pop:"
chtag -p cobfe/zosGen/src/igyvcntl.plx

# 12. Test regular git stash (without file argument)
echo ""
echo "=== TESTING: git stash (without file) ==="
git stash
echo "Tag after 'git stash':"
chtag -p cobfe/zosGen/src/igyvcntl.plx
