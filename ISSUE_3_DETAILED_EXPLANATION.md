# Issue 3: -text + Explicit Encoding No Longer Round-trips

## P1's Bug Report

> "[P1] -text plus an explicit encoding no longer round-trips.
> Add now converts these files into UTF-8, while checkout still skips encoding conversion for CRLF_BINARY. 
> I reproduced a Latin-1 file checking out as UTF-8 and immediately appearing modified. 
> On z/OS, the tagging helper can additionally label those UTF-8 bytes as EBCDIC. 
> Both conversion directions must respect the explicit encoding."

**Reference:** [convert.c.patch:80](https://github.com/zopencommunity/gitport/blob/7f3732f/stable-patches/convert.c.patch#L80)

---

## Executive Summary

**Problem:** Files with `-text` attribute AND `working-tree-encoding` don't round-trip correctly.

**Severity:** HIGH - Causes phantom modifications, breaks valid use case

**Impact:**
- User adds file → Git converts to UTF-8 ✅
- User checks out file → Git skips conversion ❌
- File now in wrong encoding (UTF-8 instead of Latin-1/ISO-8859-1)
- `git status` shows file modified (but user didn't change it!)
- On z/OS: File tagged incorrectly (UTF-8 bytes tagged as EBCDIC)

---

## Understanding the Issue

### What is `-text` Attribute?

**From Git documentation:**
```
-text     Unset text attribute (binary treatment)
          - Disables line ending conversion (CRLF ↔ LF)
          - Sets CRLF_BINARY mode internally
```

**Purpose:** Treat file as binary for line ending purposes, but...

### The Problem: Two Separate Concerns

Git has two independent conversions:

| Concern | Controlled By | Purpose |
|---------|---------------|---------|
| **Line endings** | `text` / `crlf` / `eol` | CRLF ↔ LF conversion |
| **Character encoding** | `working-tree-encoding` | Encoding conversion (e.g., Latin-1 ↔ UTF-8) |

**These are independent!** But the code conflates them.

### Current Broken Behavior

#### Scenario: `-text working-tree-encoding=ISO-8859-1`

**User's intent:**
- Don't convert line endings (leave as-is)
- DO convert encoding (ISO-8859-1 ↔ UTF-8)

**What happens:**

```bash
# File on disk: ISO-8859-1 (Latin-1) encoding
$ cat file.txt
Café  # Contains byte 0xe9 (é in Latin-1)

# .gitattributes
*.txt -text working-tree-encoding=ISO-8859-1

# Add file
$ git add file.txt
# encode_to_git() runs
# Converts: ISO-8859-1 → UTF-8
# Git object stores: UTF-8 (é as 0xc3 0xa9) ✅ CORRECT

# Checkout file
$ git checkout file.txt
# encode_to_working_tree() checks attr_action
# attr_action == CRLF_BINARY (because of -text)
# Code: if (attr_action == CRLF_BINARY) return 0;  ← SKIPS CONVERSION!
# File written: UTF-8 (é as 0xc3 0xa9) ❌ WRONG!
# Should be: ISO-8859-1 (é as 0xe9)

# Immediate phantom modification
$ git status
modified: file.txt  # But user didn't change it!
```

**Root cause:** Checkout direction skips ALL conversion when `attr_action == CRLF_BINARY`, ignoring explicit `working-tree-encoding`.

---

## The Code Problem

### Add Direction (encode_to_git) - CORRECT

**Location:** `convert.c`, `encode_to_git()` function

**Current patch (line 80):**
```c
/*
 * For -text attribute: Skip encoding conversion ONLY if no encoding is specified.
 * This allows -text to disable EOL conversion while still converting encoding
 * (e.g., EBCDIC -> UTF-8) for git objects, enabling readable git diff on mixed-codepage files.
 */
if (attr_action == CRLF_BINARY && !enc) {
    return 0;  // Skip ONLY if no encoding specified
}
```

**Logic:**
- If `-text` (CRLF_BINARY) AND no `working-tree-encoding`: Skip conversion ✅
- If `-text` (CRLF_BINARY) BUT has `working-tree-encoding`: Continue conversion ✅

**This is CORRECT!** Add direction works properly.

---

### Checkout Direction (encode_to_working_tree) - BROKEN

**Problem:** The checkout direction likely has:

```c
if (attr_action == CRLF_BINARY) {
    return 0;  // Skip conversion unconditionally ❌
}
```

**Logic:**
- If `-text` (CRLF_BINARY): Skip conversion ❌
- Ignores `working-tree-encoding` completely
- File written in UTF-8 instead of working-tree encoding

**This is WRONG!** Should match the add direction logic.

---

## P1's Reproduction

### What P1 Tested

```bash
# Setup
$ echo "Café" > file.txt
$ iconv -f UTF-8 -t ISO-8859-1 file.txt > file_latin1.txt
$ mv file_latin1.txt file.txt

# Check encoding
$ od -An -tx1 file.txt | head -1
43 61 66 e9 0a  # e9 is é in Latin-1

# .gitattributes
*.txt -text working-tree-encoding=ISO-8859-1

# Add file
$ git add file.txt
$ git commit -m "Add Latin-1 file"

# Checkout in new clone
$ git clone ...
$ cd repo
$ od -An -tx1 file.txt | head -1
43 61 66 c3 a9 0a  # c3 a9 is é in UTF-8 ❌ WRONG!

# Should be:
43 61 66 e9 0a  # e9 is é in Latin-1 ✅

# Phantom modification
$ git status
modified: file.txt  # But we just cloned!

$ git diff file.txt
# Shows the file changed (but it didn't!)
```

---

## On z/OS: Additional Problem

### z/OS File Tagging Issue

On z/OS, files have encoding tags (CCSID):

**What happens:**

```bash
# After checkout
$ ls -T file.txt
- untagged  T=off  file.txt  # Or wrong tag!

# Should be:
t ISO8859-1  T=on  file.txt
```

**Problem:**
1. File contains UTF-8 bytes (é = c3 a9)
2. But should be ISO-8859-1 (é = e9)
3. z/OS tagging helper may tag as EBCDIC (wrong!)
4. Or leave untagged
5. Result: File unreadable or corrupted

**P1 quote:**
> "On z/OS, the tagging helper can additionally label those UTF-8 bytes as EBCDIC."

---

## The Fix Required

### Principle

**Both conversion directions must respect explicit encoding:**
- Add (encode_to_git): Skip conversion ONLY if `-text` AND no `working-tree-encoding` ✅
- Checkout (encode_to_working_tree): Skip conversion ONLY if `-text` AND no `working-tree-encoding` ✅

**Symmetry is key!**

### Specific Fix

**Add Direction (Already Fixed - Line 80):**
```c
// CORRECT - Already in patch
if (attr_action == CRLF_BINARY && !enc) {
    return 0;
}
```

**Checkout Direction (Needs Fix):**

**Find the checkout conversion function** (probably `convert_to_working_tree_ca_internal` or similar):

**Current (WRONG):**
```c
if (attr_action == CRLF_BINARY) {
    return 0;  // Unconditional skip ❌
}
```

**Fixed (CORRECT):**
```c
if (attr_action == CRLF_BINARY && !ca->working_tree_encoding) {
    return 0;  // Skip ONLY if no encoding specified ✅
}
```

**Logic:**
- `-text` without encoding: Skip conversion (pure binary)
- `-text` with encoding: DO conversion (disable CRLF, keep encoding)

---

## Test Case for Issue 3

### Setup

```bash
# .gitattributes
*.txt -text working-tree-encoding=ISO-8859-1

# Create Latin-1 file
echo "Café" > test_utf8.txt
iconv -f UTF-8 -t ISO-8859-1 test_utf8.txt > test.txt
rm test_utf8.txt
```

### Test: Round-trip

```bash
# Check original encoding
od -An -tx1 test.txt
# Should show: ... e9 ... (é in Latin-1)

# Add and commit
git add test.txt
git commit -m "Latin-1 test"

# Check Git object (should be UTF-8)
HASH=$(git ls-files -s test.txt | awk '{print $2}')
git cat-file -p $HASH | od -An -tx1
# Should show: ... c3 a9 ... (é in UTF-8) ✅

# Checkout fresh
rm test.txt
git checkout test.txt

# Check encoding after checkout
od -An -tx1 test.txt
# BEFORE FIX: ... c3 a9 ... (UTF-8) ❌ WRONG
# AFTER FIX:  ... e9 ...    (Latin-1) ✅ CORRECT

# Verify no phantom modification
git status
# BEFORE FIX: modified: test.txt ❌
# AFTER FIX:  nothing to commit ✅
```

### On z/OS: Check File Tag

```bash
# After checkout
ls -T test.txt
# BEFORE FIX: untagged or wrong tag ❌
# AFTER FIX:  ISO8859-1 T=on ✅
```

---

## Impact Analysis

### Who Is Affected?

**Users with:**
1. `-text` attribute (disable CRLF conversion)
2. AND `working-tree-encoding` (non-UTF-8 encoding)
3. Files in Latin-1, ISO-8859-*, Windows-125X, etc.

**Common scenarios:**
- Legacy codebases with specific encodings
- Mixed encoding projects
- Files that shouldn't have CRLF conversion but need encoding conversion

### What Breaks?

1. **Round-trip broken:**
   - File added correctly (UTF-8 in Git)
   - File checked out incorrectly (UTF-8 in working tree)
   - Should be original encoding

2. **Phantom modifications:**
   - `git status` shows modified
   - `git diff` shows changes
   - But user didn't change anything!

3. **z/OS file tagging:**
   - Files untagged or wrong tag
   - Tools can't read files correctly
   - Corruption risk

### Workarounds (Before Fix)

**Option 1:** Don't use `-text` with `working-tree-encoding`
- Lose control over CRLF handling
- Not ideal

**Option 2:** Use `text` instead of `-text`
- Enables CRLF conversion (may not want)
- Changes file content

**Option 3:** Don't use `working-tree-encoding`
- Lose encoding conversion
- UTF-8 everywhere (may break tools)

**None are good!** The fix is needed.

---

## The Exact Code to Change

### Location Found

**File:** `git/convert.c`  
**Function:** `encode_to_worktree()`  
**Line:** 540  

### Current Code (BROKEN)

```c
static int encode_to_worktree(const char *path, const char *src, size_t src_len,
			      struct strbuf *buf, enum convert_crlf_action attr_action,
			      const char *enc)
{
	char *dst;
	size_t dst_len;
	if (attr_action == CRLF_BINARY) {  // ← LINE 540: UNCONDITIONAL SKIP ❌
		return 0;
	}

	/*
	 * No encoding is specified or there is nothing to encode.
	 * Tell the caller that the content was not modified.
	 */
	if (!enc || same_encoding(enc, default_encoding) || (src && !src_len))
		return 0;
	// ... rest of function
}
```

**Problem:** Line 540 returns immediately if `attr_action == CRLF_BINARY`, completely ignoring the `enc` parameter (working-tree-encoding).

### Required Fix

**Change line 540 from:**
```c
if (attr_action == CRLF_BINARY) {
	return 0;
}
```

**To:**
```c
if (attr_action == CRLF_BINARY && !enc) {
	return 0;
}
```

**Logic:**
- If `-text` (CRLF_BINARY) AND no encoding specified: Skip conversion ✅
- If `-text` (CRLF_BINARY) BUT has encoding: Continue to convert ✅

**This matches the add direction logic in `encode_to_git()` line 80!**

### Verification

**Check that this matches the add direction:**

```bash
# Add direction (encode_to_git) - line 418
if (attr_action == CRLF_BINARY && !enc) {
    return 0;
}

# Checkout direction (encode_to_worktree) - line 540 (AFTER FIX)
if (attr_action == CRLF_BINARY && !enc) {
    return 0;
}
```

**Perfect symmetry!** ✅

---

## Implementation Plan

### Step 1: Apply the Fix to git/convert.c

**File:** `git/convert.c`  
**Line:** 540

**Change:**
```diff
 static int encode_to_worktree(const char *path, const char *src, size_t src_len,
 			       struct strbuf *buf, enum convert_crlf_action attr_action,
 			       const char *enc)
 {
 	char *dst;
 	size_t dst_len;
-	if (attr_action == CRLF_BINARY) {
+	if (attr_action == CRLF_BINARY && !enc) {
 		return 0;
 	}
```

**Command:**
```bash
cd git
# Edit convert.c line 540
# Change: if (attr_action == CRLF_BINARY) {
# To:     if (attr_action == CRLF_BINARY && !enc) {
```

### Step 2: Update the Patch File

**File:** `stable-patches/convert.c.patch`

The patch should already have the add direction fix (line 80). We need to add the checkout direction fix.

**Add to patch:**
```diff
@@ -540,7 +540,7 @@ static int encode_to_worktree(const char *path, const char *src, size_t src_len
 {
 	char *dst;
 	size_t dst_len;
-	if (attr_action == CRLF_BINARY) {
+	if (attr_action == CRLF_BINARY && !enc) {
 		return 0;
 	}
```

### Step 3: Rebuild Git

```bash
cd git
make clean
make
```

### Step 4: Create Test

**File:** `tests/test_issue3_text_encoding_roundtrip.sh`

```bash
#!/bin/bash
# Test Issue 3: -text + working-tree-encoding round-trip

set -e

echo "╭──────────────────────────────────────────────────────────────────────────────╮"
echo "│     Test: Issue 3 - Text + Encoding Round-trip                          │"
echo "╰──────────────────────────────────────────────────────────────────────────────╯"
echo ""

TEST_DIR="/tmp/git_issue3_test_$$"
mkdir -p "$TEST_DIR"

# Trap for cleanup
trap 'cd / && rm -rf "$TEST_DIR" 2>/dev/null || true' EXIT INT TERM

cd "$TEST_DIR"

echo "Test directory: $TEST_DIR"
echo ""

# Initialize repo
git init -q
git config user.email "test@example.com"
git config user.name "Test User"

echo "═══ Step 1: Create file with -text + encoding ═══"

# Create .gitattributes
echo "*.txt -text working-tree-encoding=ISO-8859-1" > .gitattributes

# Create Latin-1 file with special character
echo "Café" > test_utf8.txt  # é in UTF-8
iconv -f UTF-8 -t ISO-8859-1 test_utf8.txt > test.txt
rm test_utf8.txt

echo "Original file (Latin-1):"
od -A x -t x1z -N 10 test.txt
echo ""

# Capture original bytes
ORIGINAL_BYTES=$(od -A n -t x1 test.txt | tr -d ' \n')
echo "Original bytes: $ORIGINAL_BYTES"
echo ""

echo "═══ Step 2: Add and commit ═══"
git add .
git commit -q -m "Initial commit"
echo "✓ Committed"
echo ""

echo "═══ Step 3: Check Git object (should be UTF-8) ═══"
HASH=$(git ls-files -s test.txt | awk '{print $2}')
echo "Object hash: $HASH"
git cat-file -p $HASH | od -A x -t x1z -N 10
echo ""

echo "═══ Step 4: Checkout fresh (should convert back) ═══"
rm test.txt
git checkout test.txt
echo "✓ Checked out"
echo ""

echo "After checkout (should be Latin-1):"
od -A x -t x1z -N 10 test.txt
echo ""

# Capture after bytes
AFTER_BYTES=$(od -A n -t x1 test.txt | tr -d ' \n')
echo "After bytes: $AFTER_BYTES"
echo ""

echo "═══ Step 5: Verify round-trip ═══"

if [ "$ORIGINAL_BYTES" = "$AFTER_BYTES" ]; then
    echo "✅ PASS: Round-trip successful!"
    echo "   Bytes match: $ORIGINAL_BYTES"
    echo ""
    
    # Verify git status shows clean
    if git status --porcelain | grep -q "test.txt"; then
        echo "❌ FAIL: git status shows modified (phantom modification)"
        git status
        exit 1
    else
        echo "✅ PASS: git status shows clean (no phantom modification)"
        EXIT_CODE=0
    fi
else
    echo "❌ FAIL: Bytes don't match!"
    echo "   Original: $ORIGINAL_BYTES"
    echo "   After:    $AFTER_BYTES"
    echo ""
    echo "   This means checkout didn't convert back to Latin-1"
    echo "   File is now UTF-8 instead of ISO-8859-1"
    EXIT_CODE=1
fi

echo ""
echo "══════════════════════════════════════════════════════════════════════════════"
if [ $EXIT_CODE -eq 0 ]; then
    echo "RESULT: Issue 3 is FIXED ✅"
else
    echo "RESULT: Issue 3 still BROKEN ❌"
fi
echo "══════════════════════════════════════════════════════════════════════════════"

exit $EXIT_CODE
```

### Step 5: Test Before Fix (Should Fail)

```bash
cd tests
chmod +x test_issue3_text_encoding_roundtrip.sh
./test_issue3_text_encoding_roundtrip.sh

# Expected: FAIL (bytes don't match, phantom modification)
```

### Step 6: Apply Fix and Test Again

```bash
# Apply fix to git/convert.c line 540
cd ../git
# ... make the change ...
make

# Test again
cd ../tests
./test_issue3_text_encoding_roundtrip.sh

# Expected: PASS (bytes match, no phantom modification)
```

### Step 7: Add to TEST_MANIFEST

```bash
echo "test_issue3_text_encoding_roundtrip.sh" >> tests/TEST_MANIFEST
```

### Step 8: Run All Tests

```bash
cd tests
./run_all_tests.sh

# Should show: 33/33 tests pass (32 + new Issue 3 test)
```

---

## Relationship to Other Issues

### Issue 5 (Clean Filters) - Same File!

**Both in `convert.c`:**
- Issue 5: `encode_to_git()` (add direction) - filter handling
- Issue 3: Both `encode_to_git()` and checkout direction - `-text` handling

**Can be applied together!**

### Similarities to Issue 4 (Blame)

**Pattern:**
- Conditional logic based on attribute
- Must respect explicit encoding
- z/OS file tagging concerns

**Lesson learned:**
- Don't skip conversions unconditionally
- Check for explicit encoding first
- Symmetry between add and checkout

---

## Expected Behavior After Fix

### Correct Flow

```
Add (working tree → Git):
  -text + encoding → Disable CRLF, Enable encoding ✅
  -text no encoding → Disable CRLF, Disable encoding ✅

Checkout (Git → working tree):
  -text + encoding → Disable CRLF, Enable encoding ✅
  -text no encoding → Disable CRLF, Disable encoding ✅
```

### Test Results

**Before fix:**
```bash
$ git add file.txt      # OK - converts to UTF-8
$ git checkout file.txt  # BAD - doesn't convert back
$ git status
modified: file.txt  ❌
```

**After fix:**
```bash
$ git add file.txt      # OK - converts to UTF-8
$ git checkout file.txt  # OK - converts back to Latin-1
$ git status
nothing to commit  ✅
```

---

## Summary

### The Bug

**Root cause:** Checkout direction skips ALL conversion when `-text` is set, ignoring explicit `working-tree-encoding`.

**Manifestation:**
- Files don't round-trip
- Phantom modifications
- Wrong file tags on z/OS
- Repository corruption risk

### The Fix

**Principle:** `-text` disables CRLF conversion, NOT encoding conversion.

**Implementation:** Add same conditional check as add direction:
```c
if (attr_action == CRLF_BINARY && !enc) {
    return 0;  // Skip ONLY if no encoding specified
}
```

**Applies to:** Checkout direction in `convert.c`

### Priority

**HIGH:**
- Breaks valid use case
- Causes phantom modifications
- Same file as Issue 5 (apply together)
- Medium complexity
- Clear fix pattern

---

## Next Steps

1. **Locate checkout conversion code** in `git/convert.c`
2. **Verify the unconditional skip** exists
3. **Apply the fix** (add `&& !enc` condition)
4. **Update patch** file
5. **Create test** for round-trip
6. **Rebuild and verify**

**Ready to fix Issue 3!** 🚀
