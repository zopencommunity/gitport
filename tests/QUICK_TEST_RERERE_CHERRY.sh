# Quick Manual Test Commands for git rerere + cherry-pick Issue
# Copy and paste these commands one by one

# 1. Setup test directory
cd /tmp
rm -rf test_rerere_cherry
mkdir test_rerere_cherry
cd test_rerere_cherry

# 2. Initialize git repo with rerere enabled
git init
git config user.name "Test"
git config user.email "test@test.com"
git config core.ignorefiletags false
git config rerere.enabled true

# 3. Create .gitattributes
echo "*.txt zos-working-tree-encoding=ibm-1047" > .gitattributes

# 4. Create initial EBCDIC file
cat > /tmp/t1.txt << 'EOF'
       IDENTIFICATION DIVISION.
       PROGRAM-ID. MAINPROG.
       WORKING-STORAGE SECTION.
       01  WS-COUNT PIC 9(5).
EOF

iconv -f ISO8859-1 -t IBM-1047 < /tmp/t1.txt > file.txt
chtag -tc 1047 file.txt

# 5. Commit
git add .gitattributes file.txt
git commit -m "Initial"

# 6. Create branch with changes
git checkout -b branch-a

cat > /tmp/t2.txt << 'EOF'
       IDENTIFICATION DIVISION.
       PROGRAM-ID. MAINPROG.
       WORKING-STORAGE SECTION.
       01  WS-COUNT PIC 9(5).
       01  WS-BRANCH-A PIC X(10).
EOF

iconv -f ISO8859-1 -t IBM-1047 < /tmp/t2.txt > file.txt
chtag -tc 1047 file.txt
git add file.txt
git commit -m "Branch A"

# 7. Go back to master and make conflicting change
git checkout master

cat > /tmp/t3.txt << 'EOF'
       IDENTIFICATION DIVISION.
       PROGRAM-ID. MAINPROG.
       WORKING-STORAGE SECTION.
       01  WS-COUNT PIC 9(5).
       01  WS-MASTER PIC X(10).
EOF

iconv -f ISO8859-1 -t IBM-1047 < /tmp/t3.txt > file.txt
chtag -tc 1047 file.txt
git add file.txt
git commit -m "Master changes"

# 8. *** FIRST TEST *** - Cherry-pick (will conflict)
echo ""
echo "=== Cherry-pick (first time - will conflict) ==="
git cherry-pick branch-a

# You should see conflict. Resolve it:
echo "Resolving conflict..."
cat > /tmp/t4.txt << 'EOF'
       IDENTIFICATION DIVISION.
       PROGRAM-ID. MAINPROG.
       WORKING-STORAGE SECTION.
       01  WS-COUNT PIC 9(5).
       01  WS-MAIN PIC X(10).
       01  WS-BRANCH-A PIC X(10).
EOF

iconv -f ISO8859-1 -t IBM-1047 < /tmp/t4.txt > file.txt
chtag -tc 1047 file.txt
git add file.txt
git cherry-pick --continue

echo "Tag after first resolution:"
chtag -p file.txt

# 9. *** SECOND TEST *** - Reset and cherry-pick again (rerere should help)
echo ""
echo "=== Resetting and cherry-pick again (rerere should auto-resolve) ==="
git reset --hard HEAD~1

# 10. Cherry-pick again - rerere should auto-resolve
git cherry-pick branch-a

# Check rerere status
echo "Rerere status:"
git rerere status

# Complete the cherry-pick
git add file.txt
git cherry-pick --continue

# 11. *** CHECK RESULT ***
echo ""
echo "=== RESULT CHECK ==="
echo "Tag after rerere auto-resolve:"
chtag -p file.txt

TAG=$(chtag -p file.txt | awk '{print $2}')
echo ""
echo "Expected: IBM-1047"
echo "Actual:   $TAG"

if [ "$TAG" != "IBM-1047" ]; then
    echo ""
    echo "❌ BUG: Tag is WRONG ($TAG instead of IBM-1047)"
    echo ""
    echo "File may appear corrupted:"
    cat file.txt | head -5
    echo ""
    echo "To fix: chtag -tc 1047 file.txt"
else
    echo ""
    echo "✅ OK: Tag is correct"
fi
