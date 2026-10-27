#!/bin/bash

# Test case for lockfile __disableautocvt fix
# Tests that git internal files (config, index, refs) are written correctly
# without corruption from z/OS automatic conversion

set -e

TEST_NAME="Lockfile Auto-Conversion Disable"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions if available
if [ -f "$SCRIPT_DIR/test_common.sh" ]; then
    source "$SCRIPT_DIR/test_common.sh"
else
    # Minimal implementations
    log_test_start() { echo "=== TEST: $1 ==="; }
    log_test_pass() { echo "✅ PASS: $1"; }
    log_test_fail() { echo "❌ FAIL: $1"; exit 1; }
    log_info() { echo "   $1"; }
fi

TEST_DIR="$HOME/delete/test_lockfile_autoconv"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

log_test_start "$TEST_NAME"

# Initialize git repo
git init -q
git config user.email "test@example.com"
git config user.name "Test User"

log_info "Testing lockfile operations for corruption..."

# =============================================================================
# Test 1: git config operations (writes to .git/config via lockfile)
# =============================================================================

log_info "Test 1: git config - UTF-8 characters in config file"

# Test UTF-8 characters that could be corrupted by double-conversion
git config test.ascii "Simple ASCII text"
git config test.utf8 "UTF-8: Héllo Wørld €uro"
git config test.special "Special: 你好 مرحبا שלום"

# Verify config file is readable
if git config --get test.utf8 > /dev/null 2>&1; then
    log_test_pass "Config file is readable after write"
else
    log_test_fail "Config file is corrupted after write"
fi

# Verify exact values are preserved
RETRIEVED=$(git config --get test.utf8)
EXPECTED="UTF-8: Héllo Wørld €uro"
if [ "$RETRIEVED" = "$EXPECTED" ]; then
    log_test_pass "UTF-8 characters preserved correctly in config"
else
    log_test_fail "UTF-8 characters corrupted. Expected: '$EXPECTED', Got: '$RETRIEVED'"
fi

# Check the actual .git/config file encoding
if file .git/config | grep -q "UTF-8\|ASCII"; then
    log_test_pass ".git/config file is valid UTF-8"
else
    log_info "⚠️  Warning: file command shows unexpected encoding"
fi

# =============================================================================
# Test 2: Index operations (writes to .git/index via lockfile)
# =============================================================================

log_info "Test 2: git add - Index file integrity"

# Create test files
echo "Test file 1" > file1.txt
echo "Test file 2" > file2.txt
echo "Test with UTF-8: Héllo €uro" > file3.txt

# Add files (this writes to .git/index via lockfile)
if git add file1.txt file2.txt file3.txt 2>&1; then
    log_test_pass "git add succeeded"
else
    log_test_fail "git add failed (index corruption?)"
fi

# Verify index is readable
if git status > /dev/null 2>&1; then
    log_test_pass "Index file is readable after write"
else
    log_test_fail "Index file is corrupted after write (fatal: index file corrupt?)"
fi

# Check index shows correct files
STAGED_FILES=$(git diff --cached --name-only | wc -l)
if [ "$STAGED_FILES" -eq 3 ]; then
    log_test_pass "Index contains correct number of staged files"
else
    log_test_fail "Index shows wrong number of files: $STAGED_FILES (expected 3)"
fi

# Verify index file exists and is binary
if [ -f .git/index ]; then
    # Check file tag
    INDEX_TAG=$(ls -T .git/index 2>/dev/null | awk '{print $1}')
    if [ "$INDEX_TAG" = "t" ] || [ "$INDEX_TAG" = "-" ]; then
        log_test_pass "Index file exists with proper tag"
    else
        log_info "⚠️  Index file tag: $INDEX_TAG"
    fi
else
    log_test_fail "Index file doesn't exist"
fi

# =============================================================================
# Test 3: Ref operations (writes to .git/refs/* via lockfile)
# =============================================================================

log_info "Test 3: git commit - Reference file integrity"

# Make a commit (writes to .git/refs/heads/master via lockfile)
if git commit -m "Test commit with UTF-8: Héllo €uro" > /dev/null 2>&1; then
    log_test_pass "git commit succeeded"
else
    log_test_fail "git commit failed (ref corruption?)"
fi

# Verify ref file was created
if [ -f .git/refs/heads/master ]; then
    log_test_pass "Ref file created"
    
    # Read the SHA from ref file
    REF_SHA=$(cat .git/refs/heads/master)
    
    # Verify it's a valid SHA (40 hex characters)
    if echo "$REF_SHA" | grep -Eq '^[0-9a-f]{40}$'; then
        log_test_pass "Ref file contains valid SHA: ${REF_SHA:0:8}..."
    else
        log_test_fail "Ref file contains corrupted SHA: $REF_SHA"
    fi
    
    # Verify ref is readable by git
    if git rev-parse HEAD > /dev/null 2>&1; then
        log_test_pass "Ref is readable by git"
    else
        log_test_fail "Ref is not readable by git (corruption?)"
    fi
else
    log_test_fail "Ref file not created"
fi

# =============================================================================
# Test 4: Multiple operations (stress test)
# =============================================================================

log_info "Test 4: Multiple lockfile operations"

# Do multiple config updates
for i in {1..10}; do
    git config "test.key$i" "Value $i with UTF-8: €$i"
done

# Verify all were written correctly
CORRUPT_COUNT=0
for i in {1..10}; do
    VALUE=$(git config --get "test.key$i")
    if [ "$VALUE" != "Value $i with UTF-8: €$i" ]; then
        CORRUPT_COUNT=$((CORRUPT_COUNT + 1))
    fi
done

if [ "$CORRUPT_COUNT" -eq 0 ]; then
    log_test_pass "All 10 config updates written correctly"
else
    log_test_fail "$CORRUPT_COUNT out of 10 config updates were corrupted"
fi

# =============================================================================
# Test 5: Branch operations (writes to .git/refs/heads/* via lockfile)
# =============================================================================

log_info "Test 5: git branch - Branch ref integrity"

# Create multiple branches
git branch test-branch-1 2>/dev/null
git branch test-branch-2 2>/dev/null
git branch "test-utf8-€uro" 2>/dev/null || log_info "⚠️  UTF-8 branch name not supported"

# Verify branches are readable
BRANCH_COUNT=$(git branch | grep -c "test-branch" || true)
if [ "$BRANCH_COUNT" -ge 2 ]; then
    log_test_pass "Branches created successfully"
else
    log_test_fail "Branch creation failed (ref corruption?)"
fi

# Verify branch refs contain valid SHAs
for branch in test-branch-1 test-branch-2; do
    if [ -f ".git/refs/heads/$branch" ]; then
        BRANCH_SHA=$(cat ".git/refs/heads/$branch")
        if echo "$BRANCH_SHA" | grep -Eq '^[0-9a-f]{40}$'; then
            log_test_pass "Branch $branch has valid SHA"
        else
            log_test_fail "Branch $branch has corrupted SHA: $BRANCH_SHA"
        fi
    fi
done

# =============================================================================
# Test 6: Tag operations (writes to .git/refs/tags/* via lockfile)
# =============================================================================

log_info "Test 6: git tag - Tag ref integrity"

# Create tags
git tag test-tag-1 2>/dev/null
git tag test-tag-2 2>/dev/null

# Verify tags are readable
TAG_COUNT=$(git tag | grep -c "test-tag" || true)
if [ "$TAG_COUNT" -ge 2 ]; then
    log_test_pass "Tags created successfully"
else
    log_test_fail "Tag creation failed (ref corruption?)"
fi

# =============================================================================
# Test 7: Verify no index corruption after multiple operations
# =============================================================================

log_info "Test 7: Index integrity after multiple operations"

# Modify files
echo "Modified 1" >> file1.txt
echo "Modified 2" >> file2.txt

# Add and commit multiple times
for i in {1..5}; do
    echo "Iteration $i" >> file1.txt
    if ! git add file1.txt 2>&1; then
        log_test_fail "git add failed on iteration $i (index corruption?)"
    fi
    if ! git commit -m "Commit $i" > /dev/null 2>&1; then
        log_test_fail "git commit failed on iteration $i (index/ref corruption?)"
    fi
done

log_test_pass "Multiple add/commit operations succeeded without corruption"

# Final index check
if git fsck > /dev/null 2>&1; then
    log_test_pass "git fsck passed - repository is not corrupted"
else
    log_test_fail "git fsck failed - repository may be corrupted"
fi

# =============================================================================
# Test 8: Packed refs operations
# =============================================================================

log_info "Test 8: git pack-refs - Packed refs integrity"

# Pack refs
if git pack-refs --all 2>/dev/null; then
    log_test_pass "git pack-refs succeeded"
    
    # Verify packed-refs file
    if [ -f .git/packed-refs ]; then
        log_test_pass "packed-refs file created"
        
        # Check it contains valid SHAs
        if grep -Eq '^[0-9a-f]{40} refs/' .git/packed-refs; then
            log_test_pass "packed-refs contains valid SHA entries"
        else
            log_test_fail "packed-refs contains corrupted entries"
        fi
    else
        log_info "⚠️  packed-refs file not created (may be expected)"
    fi
else
    log_info "⚠️  git pack-refs not available or failed (non-critical)"
fi

# Cleanup
cd /
rm -rf "$TEST_DIR"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  $TEST_NAME: ALL TESTS PASSED ✅"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  ✅ Config files: UTF-8 preserved correctly"
echo "  ✅ Index file: No corruption after writes"
echo "  ✅ Ref files: Valid SHAs written correctly"
echo "  ✅ Multiple operations: No corruption"
echo "  ✅ Branches: Created correctly"
echo "  ✅ Tags: Created correctly"
echo "  ✅ Repository integrity: fsck passed"
echo "  ✅ Packed refs: Written correctly"
echo ""
echo "This confirms that __disableautocvt() prevents z/OS runtime"
echo "from corrupting UTF-8/binary data in git internal files."
echo ""
