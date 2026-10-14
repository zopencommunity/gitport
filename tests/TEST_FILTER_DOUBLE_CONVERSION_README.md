# Test: Filter Double Conversion Investigation

## Purpose

Test whether Git double-converts filter output on z/OS, to determine:
1. Is P1's bug real? (EBCDIC stored in Git objects)
2. Is patch author's concern real? (double conversion)
3. What's the correct fix for Issue 5?

---

## Test Script

**Location:** `tests/test_filter_double_conversion.sh`

**Execute:**
```bash
./tests/test_filter_double_conversion.sh
```

---

## What the Test Does

### Setup
1. Creates Git repo with:
   - Simple 'cat' filter (pass-through, no conversion)
   - `.gitattributes`: `*.txt filter=testfilter working-tree-encoding=IBM-1047`

2. Creates EBCDIC file tagged as IBM-1047

3. Runs `git add test.txt`

### Verification
Checks Git object content for "Hello":
- **UTF-8:**   `48 65 6c 6c 6f`
- **EBCDIC:** `c8 85 93 93 96`

---

## Possible Outcomes

### Outcome 1: Git Object Contains UTF-8 ✅

```
First 5 bytes: 48 65 6c 6c 6f
Result: UTF-8 detected
```

**Meaning:**
- `encode_to_git()` IS being called
- Conversion EBCDIC → UTF-8 happened
- Git object is correct
- No bug!

**Next steps:**
- Investigate why conversion happens despite `#ifdef __MVS__`
- Check if there's another code path
- Maybe the `#ifdef` isn't effective?

---

### Outcome 2: Git Object Contains EBCDIC ❌

```
First 5 bytes: c8 85 93 93 96
Result: EBCDIC detected
```

**Meaning:**
- `encode_to_git()` was SKIPPED
- No conversion happened
- Git object stores EBCDIC
- **P1's bug confirmed!**

**Next steps:**
- Remove `#ifdef __MVS__` block from `convert.c:1612-1626`
- This restores upstream Git behavior
- Fixes repository corruption issue

---

### Outcome 3: Neither Encoding Detected ⚠️

```
First 5 bytes: [something else]
Result: Unexpected
```

**Meaning:**
- Unexpected conversion occurred
- Or file content was altered
- Need manual investigation

---

## Expected Flow Analysis

### Expected Flow (Correct Behavior)

```
1. User: git add test.txt
   └─> File: EBCDIC (c8 85 93...)

2. Git: Read file
   └─> Buffer: EBCDIC

3. Git: Apply clean filter
   └─> Filter input: EBCDIC
   └─> Filter (cat): Pass through
   └─> Filter output: EBCDIC

4. Git: encode_to_git()
   └─> Input: EBCDIC (c8 85 93...)
   └─> Converts: EBCDIC → UTF-8
   └─> Output: UTF-8 (48 65 6c...)

5. Git: Store object
   └─> Object: UTF-8 ✓
```

### With #ifdef __MVS__ Skip (Current Code)

```
1. User: git add test.txt
   └─> File: EBCDIC

2. Git: Read file
   └─> Buffer: EBCDIC

3. Git: Apply clean filter
   └─> Filter output: EBCDIC

4. Git: encode_to_git()
   └─> #ifdef __MVS__
   └─> SKIPPED!

5. Git: Store object
   └─> Object: EBCDIC ✗ (BUG!)
```

---

## The "Double Conversion" Concern

### Patch Author's Theory

> "Clean filters may output data that is already encoded (e.g., UTF-8).
> Calling encode_to_git would cause a second conversion."

**Scenario they're worried about:**
```
1. EBCDIC file
2. Smart filter converts EBCDIC → UTF-8
3. Filter outputs UTF-8
4. encode_to_git() tries to convert UTF-8 → UTF-8
5. Double conversion? Corruption?
```

**Why this shouldn't happen:**
- `encode_to_git()` has `same_encoding()` guard
- If `enc == "UTF-8"` and `default_encoding == "UTF-8"`, it returns early
- No double conversion should occur

### P1's Bug Report

> "With a required cat filter and CP037 input, my reproduction stored 
> raw EBCDIC instead of UTF-8."

**P1's scenario:**
```
1. EBCDIC file
2. Cat filter (pass-through) outputs EBCDIC
3. NO conversion happens
4. EBCDIC stored in Git object
5. Repository corruption!
```

**This is the opposite of double conversion - it's NO conversion!**

---

## What to Do Based on Results

### If UTF-8 Found (Outcome 1)

**Actions:**
1. Check code path - why does conversion happen?
2. Maybe `#ifdef __MVS__` isn't reached?
3. Maybe there's another conversion path?
4. Review `convert_to_git_filter_fd()` call sites
5. Add debug logging to understand flow

**Don't change anything yet!**

---

### If EBCDIC Found (Outcome 2)

**Actions:**
1. ✅ Confirms P1's bug
2. ✅ Confirms patch is wrong
3. Apply this fix immediately:

```c
// File: git/convert.c, lines 1612-1626
// REMOVE these lines:

#ifdef __MVS__
	/*
	 * z/OS-specific: Skip encode_to_git on filter output to avoid double conversion.
	 * On z/OS, clean filters may output data that is already encoded (e.g., UTF-8).
	 * Calling encode_to_git would cause a second conversion (UTF-8 -> IBM-1047 -> UTF-8),
	 * resulting in corrupted data in the Git object.
	 *
	 * On other platforms, this conversion is necessary and correct.
	 * See: Call #9 in debug logs for z/OS double-conversion details.
	 */
	/* Skip encode_to_git on z/OS - filter output already encoded */
#else

// ... keep encode_to_git() call ...

#endif  // ← Also remove this
```

**Result:** `encode_to_git()` always called (like upstream)

---

### If Neither Found (Outcome 3)

**Actions:**
1. Inspect test directory manually
2. Check file tags
3. Check filter script output
4. Add debug prints to Git code
5. Re-run with tracing

---

## Next Steps After Test

### Depending on Result

**UTF-8 found:**
- Investigate code flow
- May not need to change anything
- Or may need different fix

**EBCDIC found:**
- Apply fix immediately
- Rebuild Git
- Re-run test to verify
- Should show UTF-8 after fix

**Unknown:**
- Manual investigation
- Debug prints in convert.c
- Trace execution

---

## How to Run

```bash
# Make executable (if not already)
chmod +x tests/test_filter_double_conversion.sh

# Run the test
./tests/test_filter_double_conversion.sh

# Check exit code
echo $?
# 0 = UTF-8 found (investigate)
# 1 = EBCDIC found (apply fix)
# 2 = Unknown (manual investigation)
```

---

## Summary

This test will definitively answer:
1. ✅ Does P1's bug exist? (EBCDIC in objects)
2. ✅ Does double conversion happen? (corruption)
3. ✅ What's the correct fix?

**Run the test and report results!**
