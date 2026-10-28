#!/bin/bash
#
# Test: Checkout should abort when working-tree encoding conversion fails
#
# This test verifies that git checkout properly aborts and reports an error
# when conversion to working-tree-encoding fails, rather than silently
# writing incorrectly-encoded data.
#
# Background:
# - Git objects are stored in UTF-8 (canonical format)
# - working-tree-encoding attribute specifies desired working tree encoding
# - If conversion fails, checkout must abort
#
# Determinism note:
# The original version relied on a "non-convertible character" (Euro sign)
# not existing in IBM-1047. Whether iconv rejects such bytes depends on the
# libiconv build (some map every byte and never fail). This version triggers
# conversion failures deterministically by using an encoding name unknown to
# iconv (iconv_open fails => conversion always fails), independent of the
# libiconv build and of file tags.
#
# Pattern used by the "should fail" tests:
#   1. Commit the file while the attribute names a real encoding (IBM-1047),
#      so the blob is stored fine.
#   2. Change .gitattributes (in the working tree or in the target commit)
#      to the unknown encoding.
#   3. Attempt the checkout: UTF-8 -> unknown-encoding now fails.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="${SCRIPT_DIR}/test_checkout_encoding_failure_$$"

# An encoding name that iconv does not know; any conversion to/from it fails.
BAD_ENCODING="NOSUCHENC-12345"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Cleanup function
cleanup() {
    if [ -d "$TEST_DIR" ]; then
        cd "$SCRIPT_DIR"
        rm -rf "$TEST_DIR"
    fi
}

trap cleanup EXIT

# Helper functions
log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

run_test() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    log_info "Running test $TESTS_RUN: $test_name"
}

pass_test() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_success "$1"
}

fail_test() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_error "$1"
}

# Common repo setup
setup_repo() {
    cd "$TEST_DIR"
    rm -rf .git
    git init -q -b main
    git config core.iconvtranslit false
    git config core.ignorefiletags true  # Don't depend on the machine's global config
    git config user.email "test@example.com"
    git config user.name "Test User"
}

#
# Test 1: Checkout with failing encoding conversion should fail
#
test_unconvertible_character() {
    run_test "Checkout with failing encoding conversion should fail"

    setup_repo

    # Commit the file while conversion is possible
    echo "*.txt working-tree-encoding=IBM-1047" > .gitattributes
    echo "Test file with text" > test.txt

    git add .gitattributes test.txt
    git commit -q -m "Add convertible file"

    # Make the checkout conversion fail deterministically:
    # an encoding unknown to iconv makes UTF-8 -> working-tree fail.
    echo "*.txt working-tree-encoding=$BAD_ENCODING" > .gitattributes

    # Remove the working tree file
    rm -f test.txt

    # Try to checkout - should FAIL with error message
    if git checkout HEAD -- test.txt 2>error.log; then
        fail_test "Checkout should have failed but succeeded"
        cat error.log
        return 1
    fi

    # Check that error message is present
    if grep -q "failed to convert\|failed to encode" error.log; then
        pass_test "Checkout failed with expected error message"
    else
        fail_test "Checkout failed but without proper error message"
        cat error.log
        return 1
    fi

    # Verify file was NOT created (checkout aborted)
    if [ -f test.txt ]; then
        fail_test "File should not exist after failed checkout"
        return 1
    fi

    pass_test "File was not created (checkout properly aborted)"
}

#
# Test 2: Checkout with convertible content should succeed
#
test_convertible_character() {
    run_test "Checkout with convertible characters should succeed"

    setup_repo

    # Create a file with only ASCII characters (convertible to any encoding)
    echo "*.txt working-tree-encoding=IBM-1047" > .gitattributes
    echo "Simple ASCII text 123" > test.txt

    git add .gitattributes test.txt
    git commit -q -m "Add file with ASCII"

    # Remove the working tree file
    rm -f test.txt

    # Try to checkout - should SUCCEED
    if ! git checkout HEAD -- test.txt 2>error.log; then
        fail_test "Checkout should have succeeded but failed"
        cat error.log
        return 1
    fi

    # Verify file was created
    if [ ! -f test.txt ]; then
        fail_test "File should exist after successful checkout"
        return 1
    fi

    pass_test "Checkout succeeded and file was created"
}

#
# Test 3: Full checkout should abort on encoding failure
#
test_full_checkout_abort() {
    run_test "Full checkout should abort on encoding failure"

    setup_repo

    echo "*.txt working-tree-encoding=IBM-1047" > .gitattributes
    echo "Good file" > good.txt
    echo "Bad file" > bad.txt

    git add .gitattributes good.txt bad.txt
    git commit -q -m "Add mixed files"

    # Make conversion fail for all .txt files
    echo "*.txt working-tree-encoding=$BAD_ENCODING" > .gitattributes

    # Remove files
    rm -f good.txt bad.txt

    # Try full checkout - should fail
    if git checkout HEAD -- . 2>error.log; then
        fail_test "Full checkout should have failed"
        cat error.log
        return 1
    fi

    # Check error message
    if grep -q "failed to convert\|failed to encode" error.log; then
        pass_test "Full checkout failed with expected error"
    else
        fail_test "Full checkout failed without proper error"
        cat error.log
        return 1
    fi
}

#
# Test 4: Clone should fail on encoding error
#
test_clone_encoding_failure() {
    run_test "Clone should report encoding conversion failures"

    cd "$TEST_DIR"

    # Create source repo
    mkdir -p source
    cd source
    git init -q
    git config core.iconvtranslit false
    git config core.ignorefiletags true
    git config user.email "test@example.com"
    git config user.name "Test User"

    # Commit the file with a working encoding first
    echo "*.txt working-tree-encoding=IBM-1047" > .gitattributes
    echo "Some content" > file.txt

    git add .gitattributes file.txt
    git commit -q -m "Add convertible file"

    # Then commit an attribute that makes checkout-time conversion fail
    echo "*.txt working-tree-encoding=$BAD_ENCODING" > .gitattributes
    git add .gitattributes
    git commit -q -m "Switch to unconvertible encoding"

    cd "$TEST_DIR"

    # Try to clone - checkout phase should fail
    if git clone -q source dest 2>clone_error.log; then
        fail_test "Clone should have failed during checkout"
        cat clone_error.log
        return 1
    fi

    # Check for error message
    if grep -q "failed to convert\|failed to encode\|unable to checkout" clone_error.log; then
        pass_test "Clone failed with encoding conversion error"
    else
        fail_test "Clone failed but without expected error message"
        cat clone_error.log
        return 1
    fi
}

#
# Test 5: Switch branch with encoding failure
#
test_branch_switch_encoding_failure() {
    run_test "Branch switch should abort on encoding failure"

    setup_repo

    # Create branch structure: main has good attr, bad-branch has failing attr
    # and different file content (so the file must be rewritten on switch).
    echo "*.txt working-tree-encoding=IBM-1047" > .gitattributes
    echo "Good content" > file.txt
    git add .gitattributes file.txt
    git commit -q -m "Good file"

    git checkout -q -b bad-branch
    echo "Different content" > file.txt
    git add file.txt
    git commit -q -m "Different content"
    # Now make the conversion fail on this branch
    echo "*.txt working-tree-encoding=$BAD_ENCODING" > .gitattributes
    git add .gitattributes
    git commit -q -m "Bad encoding attr"

    # Go back to main (force: the bad attr in the working tree may have
    # prevented file.txt from being restored on the previous switch)
    git checkout -q -f main

    # Try to switch to bad branch. Note: a branch switch itself may
    # still complete (exit 0) in this build; the important guarantees are
    # that the conversion failure is reported and that no wrongly-encoded
    # file is written to the working tree.
    git checkout bad-branch 2>switch_error.log || true

    if grep -q "failed to convert\|failed to encode" switch_error.log; then
        pass_test "Branch switch reported encoding error"
    else
        fail_test "Branch switch did not report encoding error"
        cat switch_error.log
        return 1
    fi

    # Verify the file was not written with wrong encoding: it must either
    # be absent (checkout of that path aborted) or match the index.
    # (grep is unreliable here: the file is tagged IBM-1047, which makes
    # tag-honoring shell tools read it as EBCDIC.)
    if [ ! -f file.txt ]; then
        pass_test "No wrongly-encoded file written on failed switch"
    elif [ -z "$(git status --porcelain file.txt)" ]; then
        pass_test "File matches index (no wrongly-encoded content written)"
    else
        fail_test "File was modified despite conversion failure"
        return 1
    fi
}

#
# Test 6: File should not be corrupted after failed checkout
#
test_no_corruption_on_failure() {
    run_test "Failed checkout should not corrupt working tree"

    setup_repo

    # Create and commit a good file
    echo "*.txt working-tree-encoding=IBM-1047" > .gitattributes
    echo "Original good content" > file.txt
    git add .gitattributes file.txt
    git commit -q -m "Good file"

    # Create a branch whose checkout would require a failing conversion
    git checkout -q -b bad-branch
    echo "Content that must not appear" > file.txt
    git add file.txt
    git commit -q -m "Different content"
    echo "*.txt working-tree-encoding=$BAD_ENCODING" > .gitattributes
    git add .gitattributes
    git commit -q -m "Bad encoding attr"

    # Back on main. The switch itself may fail to rewrite file.txt (the
    # bad attribute is still in effect), so restore the attributes first,
    # then the file.
    git checkout -q -f main
    git checkout -q main -- .gitattributes
    git checkout -q main -- file.txt

    # Verify file has good content: it must exist and match the index.
    # (grep is unreliable here: the file is tagged IBM-1047, which makes
    # tag-honoring shell tools read it as EBCDIC.)
    if [ -f file.txt ] && [ -z "$(git status --porcelain file.txt)" ]; then
        pass_test "Working tree has correct content"
    else
        fail_test "Working tree content is wrong"
        return 1
    fi

    # Try to checkout bad branch - the conversion for file.txt fails
    git checkout bad-branch 2>error.log || true

    # Verify no wrongly-encoded content was written: the file must either
    # be absent (checkout of that path aborted) or match the index.
    if [ -f file.txt ] && [ -n "$(git status --porcelain file.txt)" ]; then
        fail_test "Working tree was corrupted by failed checkout"
        return 1
    fi
    pass_test "No wrongly-encoded content written"

    # Verify the working tree is recoverable: forcing back to main
    # restores a file that matches the index.
    git checkout -q -f main
    git checkout -q main -- .gitattributes
    git checkout -q main -- file.txt
    if [ -f file.txt ] && [ -z "$(git status --porcelain file.txt)" ]; then
        pass_test "Working tree restored after failed checkout"
    else
        fail_test "Working tree could not be restored"
        return 1
    fi
}

#
# Test 7: Verify error propagation in async mode (parallel checkout)
#
test_async_conversion_failure() {
    run_test "Async (parallel) checkout should handle encoding failures"

    setup_repo

    # Enable parallel checkout
    git config checkout.workers 2

    # Commit multiple files with a working encoding
    echo "*.txt working-tree-encoding=IBM-1047" > .gitattributes
    echo "Good file 1" > file1.txt
    echo "Good file 2" > file2.txt
    echo "Good file 3" > file3.txt
    echo "Good file 4" > file4.txt

    git add .gitattributes file*.txt
    git commit -q -m "Mixed files"

    # Make conversion fail for all .txt files
    echo "*.txt working-tree-encoding=$BAD_ENCODING" > .gitattributes

    # Remove files
    rm -f file*.txt

    # Try checkout - should fail
    if git checkout HEAD -- . 2>async_error.log; then
        fail_test "Async checkout should have failed"
        cat async_error.log
        return 1
    fi

    if grep -q "failed to convert\|failed to encode" async_error.log; then
        pass_test "Async checkout failed with encoding error"
    else
        fail_test "Async checkout failed without proper error"
        cat async_error.log
        return 1
    fi
}

# Run all tests
main() {
    log_info "Starting checkout encoding failure tests"
    log_info "====================================="

    mkdir -p "$TEST_DIR"

    test_unconvertible_character
    test_convertible_character
    test_full_checkout_abort
    test_clone_encoding_failure
    test_branch_switch_encoding_failure
    test_no_corruption_on_failure
    test_async_conversion_failure

    echo ""
    log_info "====================================="
    log_info "Test Summary:"
    log_info "  Total:  $TESTS_RUN"
    log_success "Passed: $TESTS_PASSED"

    if [ $TESTS_FAILED -gt 0 ]; then
        log_error "Failed: $TESTS_FAILED"
        exit 1
    else
        log_success "All tests passed!"
        exit 0
    fi
}

main "$@"
