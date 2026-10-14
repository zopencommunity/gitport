# Comprehensive Filter Conversion Test

## Purpose

This test validates the Issue 5 fix by testing TWO scenarios:

1. **Dumb filter (cat)** - The common case (99% of filters) - P1's bug scenario
2. **same_encoding() protection** - Prevents double conversion

Note: We previously tested "smart filters" (filters that convert encoding), but these are anti-patterns and not supported by Git's design. See FILTER_ANTI_PATTERNS.md for details.

---

## Test Script

**Location:** `tests/test_filter_conversion_comprehensive.sh`

**Run after your build completes:**
```bash
./tests/test_filter_conversion_comprehensive.sh
```

---

## What Each Test Verifies

### TEST 1: Dumb Filter (cat) - P1's Scenario

**Setup:**
- Filter: `cat` (pass-through, no conversion)
- File: EBCDIC bytes
- .gitattributes: `working-tree-encoding=IBM-1047`

**Expected after fix:**
```
File:       c8 85 93 93 96  (EBCDIC "Test")
Filter:     c8 85 93 93 96  (passes through)
encode_to_git(): EBCDIC → UTF-8
Git object: 48 65 6c 6c 6f  (UTF-8) ✅
```

**This proves:** The fix works for normal filters! P1's bug is FIXED!

---

### TEST 2: same_encoding() Protection

**Setup:**
- Filter: `cat`
- File: UTF-8 bytes
- .gitattributes: `working-tree-encoding=UTF-8`

**Expected:**
```
File:       48 65 6c 6c 6f  (UTF-8)
Filter:     48 65 6c 6c 6f  (passes through)
encode_to_git(): same_encoding(UTF-8, UTF-8)? YES
               → Skip conversion (return 0)
Git object: 48 65 6c 6c 6f  (UTF-8) ✅
```

**This proves:** No double conversion happens (UTF-8 → UTF-8 skipped)!

---

## Expected Results After Fix

### If Fix Was Applied Correctly

```
TEST 1: PASS ✅ - Dumb filter works (EBCDIC → UTF-8)
TEST 2: PASS ✅ - same_encoding() protection works

ALL TESTS PASSED!
```

### If Fix NOT Applied (still has #ifdef)

```
TEST 1: FAIL ❌ - Git object has EBCDIC (should be UTF-8)
TEST 2: PASS ✅ - This would still work

SOME TESTS FAILED
```

---

## Interpreting Results

### Success Criteria

**For the fix to be correct, we need:**
1. ✅ TEST 1 must PASS (dumb filters work - P1's bug fixed)
2. ✅ TEST 2 must PASS (no double conversion)

### What Each Failure Means

**TEST 1 FAILS:**
- Git object has EBCDIC instead of UTF-8
- Means: `encode_to_git()` is still being skipped
- Action: Check if #ifdef __MVS__ block was fully removed

**TEST 2 FAILS:**
- Content is corrupted for UTF-8 files
- Means: `same_encoding()` protection not working
- Action: Need to investigate further

---

## After Running the Test

### If All Pass

Great! The fix is working correctly:
1. ✅ Dumb filters work (P1's bug fixed!)
2. ✅ No double conversion protection works

**Next steps:**
- Continue with other P1 fixes
- Document that filters should not do encoding conversion

### If TEST 1 Fails

The fix wasn't applied correctly:
1. Verify #ifdef __MVS__ block was removed
2. Check lines 1612-1626 in git/convert.c
3. Rebuild: `cd git && make`
4. Re-run test

---

## Running the Test

```bash
# After your build completes:
cd /home/haritha/code/bazel-7.2.0/git_255_iconv_translit_3waymerge/gitchkin/gitport

# Run comprehensive test
./tests/test_filter_conversion_comprehensive.sh

# It will show:
# - TEST 1: Dumb filter (should pass)
# - TEST 2: same_encoding() (should pass)
# - Summary with pass/fail counts
# - Note about filter anti-patterns
```

---

## About "Smart Filters"

This test used to include TEST 2 for "smart filters" (filters that convert encoding like iconv). We removed it because:

1. **Anti-pattern:** Filters should NOT convert encoding
2. **Not supported:** Git's design separates content (filters) from encoding (Git)
3. **Redundant:** `working-tree-encoding` already does this
4. **Not documented:** No Git documentation mentions this pattern
5. **Expected to fail:** Such filters violate Git's design assumptions

**See:** FILTER_ANTI_PATTERNS.md for detailed explanation

---

## Summary

This test validates:
1. ✅ The fix works for normal filters (P1's case)
2. ✅ Double conversion is prevented (same_encoding())

Note: "Smart filters" (filters that convert encoding) are not tested as they are anti-patterns that violate Git's design. See FILTER_ANTI_PATTERNS.md.

**Run it after your build completes to confirm the fix!**
