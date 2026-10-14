# Git Filter Anti-Patterns

## Purpose

This document explains why certain filter patterns are incorrect and should be avoided, particularly filters that perform encoding conversion.

---

## Anti-Pattern: Filters That Convert Encoding

### What Is This Anti-Pattern?

Writing Git clean/smudge filters that convert character encoding (e.g., EBCDIC ↔ UTF-8).

### Example of Anti-Pattern (WRONG)

```bash
# .gitattributes
*.txt filter=badfilter working-tree-encoding=IBM-1047

# .git/config
[filter "badfilter"]
    clean = iconv -f IBM-1047 -t UTF-8    # ← WRONG! Filter converts encoding
    smudge = iconv -f UTF-8 -t IBM-1047
```

**Why this exists:** Some users think filters should handle encoding conversion.

**Why it's wrong:** Violates Git's separation of concerns.

---

## Why This Is an Anti-Pattern

### 1. Violates Git's Design

**Git separates two concerns:**

| Concern | Responsible Component | Purpose |
|---------|----------------------|---------|
| **Content transformation** | Filters (clean/smudge) | Keywords, line endings, compression, encryption |
| **Encoding conversion** | Git's encoding system | Working-tree-encoding ↔ UTF-8 |

**The flow:**
```
Checkin:  Working file → Filter (content) → encode_to_git() (encoding) → Git object (UTF-8)
Checkout: Git object (UTF-8) → encode_to_working_tree() (encoding) → Filter (content) → Working file
```

**Filters should NOT do encoding conversion** - that's Git's job!

---

### 2. Redundant with working-tree-encoding

**Git already has a mechanism for encoding:**

```bash
# .gitattributes
*.txt working-tree-encoding=IBM-1047
```

**This tells Git:**
- Working tree files use IBM-1047 encoding
- Git converts IBM-1047 → UTF-8 on checkin
- Git converts UTF-8 → IBM-1047 on checkout

**No filter needed for encoding conversion!**

---

### 3. Creates Ambiguity

**With both filter conversion AND working-tree-encoding:**

```bash
# .gitattributes
*.txt filter=myfilter working-tree-encoding=IBM-1047

# Filter also converts encoding
[filter "myfilter"]
    clean = iconv -f IBM-1047 -t UTF-8
```

**Who converts the encoding?**
- Filter converts EBCDIC → UTF-8
- Then Git's `encode_to_git()` runs
- Git thinks input is IBM-1047 but it's UTF-8
- **Result: Corruption!**

---

### 4. Not Documented or Supported

**Upstream Git documentation:**
- ✅ Filters: Documented in gitattributes(5)
- ✅ working-tree-encoding: Documented in gitattributes(5)
- ❌ Filters that convert encoding: **Not mentioned anywhere!**

**Common filter examples:**
- git-lfs (large file storage)
- git-crypt (encryption)
- keyword expansion ($Id$, $Date$)
- line ending normalization

**None of these convert encoding!**

---

### 5. Causes Corruption

**What happens with encoding-converting filter:**

```
File on disk:     EBCDIC (c8 85 93 93 96)
Filter runs:      Converts to UTF-8 (48 65 6c 6c 6f)
encode_to_git():  Thinks it's IBM-1047, tries to convert
                  Interprets UTF-8 bytes as IBM-1047
                  Produces garbage
Git object:       Corrupted data ❌
```

---

## The Correct Approach

### Use working-tree-encoding (No Filter)

**For simple encoding conversion:**

```bash
# .gitattributes
*.txt working-tree-encoding=IBM-1047
```

**That's it!** Git handles everything:
- Converts IBM-1047 → UTF-8 on checkin
- Converts UTF-8 → IBM-1047 on checkout
- Git objects always contain UTF-8

---

### Use Filter for Content (Not Encoding)

**If you need BOTH encoding AND content transformation:**

```bash
# .gitattributes
*.txt filter=goodfilter working-tree-encoding=IBM-1047

# .git/config
[filter "goodfilter"]
    clean = sed 's/$Id$//'           # ← Good! Removes keywords
    smudge = sed 's/$Id$/$Id: 123/'  # ← Good! Adds keywords
```

**This is correct because:**
- Filter does content transformation (keywords)
- Git does encoding conversion (working-tree-encoding)
- Each component does its job
- No overlap or ambiguity

---

## Historical Context: The #ifdef __MVS__ Bug

### What Happened

In z/OS Git port, someone added this code to `convert.c`:

```c
#ifdef __MVS__
  /* Skip encode_to_git on z/OS - filter output already encoded */
#else
  encode_to_git(...);
#endif
```

**Why they did it:**
- They tested a filter that converted EBCDIC → UTF-8
- They saw corruption
- They thought `encode_to_git()` was causing it
- They added `#ifdef __MVS__` to skip it
- This "fixed" their encoding-converting filter

**The problem:**
- ✅ Fixed encoding-converting filters (anti-pattern)
- ❌ **Broke normal filters** (cat, sed, awk)
- ❌ Caused **repository corruption** for legitimate use cases

### P1's Bug Report

**P1 reported (Issue 5):**
> "with a required cat filter and CP037 input, my reproduction stored raw EBCDIC instead of UTF-8"

**P1's scenario:**
```bash
# Cat filter - does NOT convert encoding
[filter "catfilter"]
    clean = cat
    smudge = cat
```

**What should happen:**
```
EBCDIC file → cat filter → EBCDIC output → encode_to_git() → UTF-8 in Git object ✅
```

**What happened with #ifdef __MVS__:**
```
EBCDIC file → cat filter → EBCDIC output → (skipped) → EBCDIC in Git object ❌
```

**Result:** Repository corruption!

### The Fix

**Remove the #ifdef __MVS__ block:**

```c
encode_to_git(...);  // Always call
```

**Result:**
- ✅ Normal filters (cat, sed) work correctly
- ✅ Git objects contain UTF-8
- ✅ No repository corruption
- ❌ Encoding-converting filters break (but they're anti-patterns anyway!)

---

## Real-World Guidance

### If You're Writing a Filter

**DO:**
- ✅ Transform content (keywords, line endings, compression, encryption)
- ✅ Return output in the **same encoding** as input
- ✅ Let Git handle encoding via `working-tree-encoding`
- ✅ Test with files that have `working-tree-encoding` set

**DON'T:**
- ❌ Convert character encoding (EBCDIC ↔ UTF-8)
- ❌ Assume input or output is UTF-8
- ❌ Duplicate Git's encoding functionality
- ❌ Use `iconv` or similar in filters

### If You Need Both Filter and Encoding

**Correct pattern:**

```bash
# .gitattributes
*.txt filter=myfilter working-tree-encoding=IBM-1047

# Filter does content transformation only
[filter "myfilter"]
    clean = remove-keywords.sh
    smudge = add-keywords.sh
```

**Git's processing order:**
```
Checkin:
  1. Read file (IBM-1047)
  2. Run clean filter (output still IBM-1047)
  3. encode_to_git() converts IBM-1047 → UTF-8
  4. Store in Git object

Checkout:
  1. Read Git object (UTF-8)
  2. encode_to_working_tree() converts UTF-8 → IBM-1047
  3. Run smudge filter (input/output IBM-1047)
  4. Write file
```

---

## Why same_encoding() Doesn't Help

### Some might think:

> "But Git has `same_encoding()` that skips conversion if source and target are the same. Won't that prevent double conversion?"

**Yes, but only if encodings match!**

**With encoding-converting filter:**

```
Filter output: UTF-8 (actual bytes)
Git expects:   IBM-1047 (from working-tree-encoding attribute)
same_encoding(IBM-1047, UTF-8)? NO
→ Git tries to convert
→ Corruption!
```

**The problem:**
- Git doesn't know filter converted encoding
- Git trusts `working-tree-encoding` attribute
- Mismatch causes corruption

**Solution:** Don't convert in filter!

---

## Testing

### Good Test Cases

**TEST 1: Dumb filter (cat) with EBCDIC:**
```bash
# Setup
*.txt filter=catfilter working-tree-encoding=IBM-1047
[filter "catfilter"]
    clean = cat

# Test
echo "Test" | iconv -f UTF-8 -t IBM-1047 > test.txt
git add test.txt

# Verify
git cat-file -p $(git ls-files -s test.txt | awk '{print $2}') | od -t x1
# Should show UTF-8 bytes (48 65 73 74)
```

**TEST 2: UTF-8 file with UTF-8 encoding (same_encoding test):**
```bash
# Setup
*.txt working-tree-encoding=UTF-8

# Test
echo "Test" > test.txt  # Already UTF-8
git add test.txt

# Verify
# Should store UTF-8 without double conversion
```

### Anti-Pattern Test (Don't Do This!)

```bash
# Setup (WRONG)
*.txt filter=badfilter working-tree-encoding=IBM-1047
[filter "badfilter"]
    clean = iconv -f IBM-1047 -t UTF-8  # ← ANTI-PATTERN

# Test
echo "Test" | iconv -f UTF-8 -t IBM-1047 > test.txt
git add test.txt

# Result: Corruption expected (filter violates design)
```

---

## Summary

### Anti-Patterns to Avoid

1. ❌ Filters that convert encoding
2. ❌ Skipping `encode_to_git()` on z/OS
3. ❌ Platform-specific encoding hacks
4. ❌ Duplicating `working-tree-encoding` functionality

### Correct Patterns

1. ✅ Use `working-tree-encoding` for encoding conversion
2. ✅ Use filters for content transformation only
3. ✅ Let Git handle encoding
4. ✅ Test with real non-UTF-8 files

### Key Takeaway

**Filters transform content, Git handles encoding.**

Don't mix the two!

---

## References

- **Git documentation:** gitattributes(5)
- **Issue 5 analysis:** ISSUE_5_SMART_FILTERS_ANALYSIS.md
- **P1's bug report:** Issue #187, Comment by P1
- **Fix details:** ISSUE_5_FIX_COMPLETE_VERIFIED.md

---

## Questions?

If you're unsure whether your filter design is correct:

1. Does your filter use `iconv` or similar? → **Probably wrong**
2. Does your filter change character encoding? → **Wrong**
3. Is your filter doing what `working-tree-encoding` does? → **Redundant**
4. Does your filter transform content (not encoding)? → **Correct!**

**When in doubt:** Use `working-tree-encoding`, not filters, for encoding.
