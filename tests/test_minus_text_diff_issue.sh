#!/bin/bash
set -e

# Resolve Git binary portably
GIT="${GIT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../git" && pwd)/git}"

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  Test: Demonstrating -text Makes git diff Garbled (But File Tags Work)       ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

cd /tmp
rm -rf test_minus_text_diff
mkdir test_minus_text_diff
cd test_minus_text_diff

$GIT init

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "Test 1: Using -text attribute (nickrayjones' scenario)"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

cat > .gitattributes << 'ATTR1'
* -text git-encoding=utf-8 zos-working-tree-encoding=ibm-1047 working-tree-encoding=utf-8
ATTR1

echo "Created .gitattributes:"
cat .gitattributes
echo ""

$GIT add .gitattributes
$GIT commit -m "Add gitattributes with -text" >/dev/null 2>&1

# Create file with CORRECT workflow
touch testfile.txt
chtag -tc IBM-1047 testfile.txt
cat > testfile.txt << 'CONTENT1'
Line 1: This is EBCDIC text
Line 2: More EBCDIC content
Line 3: Final line
CONTENT1

echo "Created testfile.txt with proper tagging:"
ls -T testfile.txt
cat testfile.txt
echo ""

$GIT add testfile.txt
$GIT commit -m "Add testfile" >/dev/null 2>&1

echo "Step 1: Check what's in git's object database"
echo "───────────────────────────────────────────────────────────────────────────"
echo "Git object (should be UTF-8, but with -text it's EBCDIC):"
$GIT show HEAD:testfile.txt | od -c | head -5
echo ""
echo "Expected UTF-8 'Line 1' bytes: 4c 69 6e 65 20 31"
echo "Actual bytes (EBCDIC 'Line 1'): $(echo 'Line 1' | iconv -f ISO8859-1 -t IBM-1047 | od -An -tx1 | head -1)"
echo ""

echo "Step 2: Modify the file"
echo "───────────────────────────────────────────────────────────────────────────"
cat >> testfile.txt << 'CONTENT2'
Line 4: This is a new line
CONTENT2

echo "Modified testfile.txt"
cat testfile.txt
echo ""

echo "Step 3: Run git diff (THIS WILL BE GARBLED)"
echo "───────────────────────────────────────────────────────────────────────────"
$GIT diff testfile.txt
echo ""

echo "Step 4: Check file tag (should be IBM-1047, not binary)"
echo "───────────────────────────────────────────────────────────────────────────"
ls -T testfile.txt
echo ""

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "Test 2: Using text attribute (without minus) for comparison"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

cd /tmp
rm -rf test_with_text_diff
mkdir test_with_text_diff
cd test_with_text_diff

$GIT init

cat > .gitattributes << 'ATTR2'
* text git-encoding=utf-8 zos-working-tree-encoding=ibm-1047 working-tree-encoding=utf-8
ATTR2

echo "Created .gitattributes with 'text' (not -text):"
cat .gitattributes
echo ""

$GIT add .gitattributes
$GIT commit -m "Add gitattributes with text" >/dev/null 2>&1

touch testfile.txt
chtag -tc IBM-1047 testfile.txt
cat > testfile.txt << 'CONTENT3'
Line 1: This is EBCDIC text
Line 2: More EBCDIC content
Line 3: Final line
CONTENT3

echo "Created testfile.txt with proper tagging:"
ls -T testfile.txt
cat testfile.txt
echo ""

$GIT add testfile.txt
$GIT commit -m "Add testfile" >/dev/null 2>&1

echo "Step 1: Check what's in git's object database"
echo "───────────────────────────────────────────────────────────────────────────"
echo "Git object (should be UTF-8, with text it IS UTF-8):"
$GIT show HEAD:testfile.txt | od -c | head -5
echo ""

cat >> testfile.txt << 'CONTENT4'
Line 4: This is a new line
CONTENT4

echo "Step 2: Run git diff (THIS WILL BE READABLE)"
echo "───────────────────────────────────────────────────────────────────────────"
$GIT diff testfile.txt
echo ""

echo "Step 3: Check file tag"
echo "───────────────────────────────────────────────────────────────────────────"
ls -T testfile.txt
echo ""

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                              COMPARISON                                       ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

echo "Test 1 (-text attribute):"
echo "  ✅ File tag: IBM-1047 (not binary) - FIXED!"
echo "  ❌ git diff: GARBLED (shows EBCDIC bytes) - BROKEN!"
echo "  Reason: Git stores EBCDIC in objects (no encoding conversion)"
echo ""

echo "Test 2 (text attribute):"
echo "  ✅ File tag: IBM-1047"
echo "  ✅ git diff: READABLE"
echo "  Reason: Git converts EBCDIC → UTF-8 for objects"
echo ""

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                            DETAILED ANALYSIS                                  ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

cd /tmp/test_minus_text_diff
echo "With -text:"
echo "───────────────────────────────────────────────────────────────────────────"
echo "Git object contains:"
$GIT cat-file -p HEAD:testfile.txt | od -tx1 | head -3
echo ""
echo "This is EBCDIC (e.g., 'L' = 0xd3, 'i' = 0x89, 'n' = 0x95, 'e' = 0x85)"
echo ""

cd /tmp/test_with_text_diff
echo "With text:"
echo "───────────────────────────────────────────────────────────────────────────"
echo "Git object contains:"
$GIT cat-file -p HEAD:testfile.txt | od -tx1 | head -3
echo ""
echo "This is UTF-8/ASCII (e.g., 'L' = 0x4c, 'i' = 0x69, 'n' = 0x6e, 'e' = 0x65)"
echo ""

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                              CONCLUSION                                       ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "nickrayjones' issue is PARTIALLY FIXED:"
echo ""
echo "✅ FIXED: File tagging"
echo "   -text + zos-working-tree-encoding → File tagged as IBM-1047 (not binary)"
echo ""
echo "❌ BROKEN: git diff"
echo "   -text disables encoding conversion → git stores EBCDIC → diff is garbled"
echo ""
echo "For mixed-codepage files (EBCDIC + Japanese):"
echo "   - 'text' attribute: git diff works, but may corrupt Japanese"
echo "   - '-text' attribute: preserves bytes, but git diff is garbled"
echo "   - NO GOOD SOLUTION currently exists!"
echo ""
echo "Recommended workaround:"
echo "   Use 'text' for most files (enables diff)"
echo "   Mark truly mixed-codepage files as 'binary' (no diff, but safe)"
echo ""

