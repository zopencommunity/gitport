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
# - If conversion fails (e.g., character not representable), checkout must abort
# - Without proper error handling, checkout would write UTF-8 data but tag as target encoding
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="${SCRIPT_DIR}/test_checkout_encoding_failure_$$"

# Colors for output
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

# Setup test repository
setup_repo() {
    log_info "Setting up test repository in $TEST_DIR"
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"
    
    # Enable transliteration for some tests
    git config core.iconvtranslit false
}

#
# Test 1: Checkout with unconvertible character should fail
#
test_unconvertible_character() {
    run_test "Checkout with unconvertible character should fail"
    
    cd "$TEST_DIR"
    rm -rf .git
    git init -q
    git config core.iconvtranslit false
    git config user.email "test@example.com"
    git config user.name "Test User"
    
    # Create a file with a character that cannot be converted to IBM-1047
    # Euro sign (€) in UTF-8 is 0xE2 0x82 0xAC
    # This character does not exist in IBM-1047 EBCDIC
    echo "*.txt working-tree-encoding=IBM-1047" > .gitattributes
    printf "Test file with Euro: \xE2\x82\xAC\n" > test.txt
    
    git add .gitattributes test.txt
    git commit -q -m "Add file with unconvertible character"
    
    # Remove the working tree file
    rm -f test.txt
    
    # Try to checkout - should FAIL with error message
    if git checkout HEAD -- test.txt 2>error.log; then
        fail_test "Checkout should have failed but succeeded"
        cat error.log
        return 1
    fi
    
    # Check that error message is present
    if grep -q "failed to convert" error.log; then
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
    
    cd "$TEST_DIR"
    rm -rf .git
    git init -q
    git config core.iconvtranslit false
    git config user.email "test@example.com"
    git config user.name "Test User"
    
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
    
    cd "$TEST_DIR"
    rm -rf .git
    git init -q
    git config core.iconvtranslit false
    git config user.email "test@example.com"
    git config user.name "Test User"
    
    echo "*.txt working-tree-encoding=IBM-1047" > .gitattributes
    echo "Good file" > good.txt
    printf "Bad file: \xE2\x82\xAC\n" > bad.txt
    
    git add .gitattributes good.txt bad.txt
    git commit -q -m "Add mixed files"
    
    # Remove files
    rm -f good.txt bad.txt
    
    # Try full checkout - should fail
    if git checkout HEAD -- . 2>error.log; then
        fail_test "Full checkout should have failed"
        cat error.log
        return 1
    fi
    
    # Check error message
    if grep -q "failed to convert" error.log; then
        pass_test "Full checkout failed with expected error"
    else
        fail_test "Full checkout failed without proper error"
        cat error.log
        return 1
    fi
}

#
# Test 4: Clone should fail on encoding error (if file contains unconvertible chars)
#
test_clone_encoding_failure() {
    run_test "Clone should report encoding conversion failures"
    
    cd "$TEST_DIR"
    
    # Create source repo
    mkdir -p source
    cd source
    git init -q
    git config core.iconvtranslit false
    git config user.email "test@example.com"
    git config user.name "Test User"
    
    echo "*.txt working-tree-encoding=IBM-1047" > .gitattributes
    printf "Unconvertible: \xE2\x82\xAC\n" > file.txt
    
    git add .gitattributes file.txt
    git commit -q -m "Add unconvertible file"
    
    cd "$TEST_DIR"
    
    # Try to clone - checkout phase should fail
    if git clone -q source dest 2>clone_error.log; then
        fail_test "Clone should have failed during checkout"
        cat clone_error.log
        return 1
    fi
    
    # Check for error message
    if grep -q "failed to convert\|unable to checkout" clone_error.log; then
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
    
    cd "$TEST_DIR"
    rm -rf .git
    git init -q
    git config core.iconvtranslit false
    git config user.email "test@example.com"
    git config user.name "Test User"
    
    # Create branch with good file
    echo "*.txt working-tree-encoding=IBM-1047" > .gitattributes
    echo "Good content" > file.txt
    git add .gitattributes file.txt
    git commit -q -m "Good file"
    
    # Create branch with bad file
    git checkout -q -b bad-branch
    printf "Bad content: \xE2\x82\xAC\n" > file.txt
    git add file.txt
    git commit -q -m "Bad file"
    
    # Go back to main
    git checkout -q main
    
    # Try to switch to bad branch - should fail
    if git checkout bad-branch 2>switch_error.log; then
        fail_test "Branch switch should have failed"
        cat switch_error.log
        return 1
    fi
    
    if grep -q "failed to convert" switch_error.log; then
        pass_test "Branch switch failed with encoding error"
    else
        fail_test "Branch switch failed without proper error"
        cat switch_error.log
        return 1
    fi
    
    # Verify we're still on main branch
    current_branch=$(git branch --show-current)
    if [ "$current_branch" = "main" ]; then
        pass_test "Stayed on original branch after failed switch"
    else
        fail_test "Branch changed despite checkout failure"
        return 1
    fi
}

#
# Test 6: File should not be corrupted after failed checkout
#
test_no_corruption_on_failure() {
    run_test "Failed checkout should not corrupt working tree"
    
    cd "$TEST_DIR"
    rm -rf .git
    git init -q
    git config core.iconvtranslit false
    git config user.email "test@example.com"
    git config user.name "Test User"
    
    echo "*.txt working-tree-encoding=IBM-1047" > .gitattributes
    
    # Create and commit a good file
    echo "Original good content" > file.txt
    git add .gitattributes file.txt
    git commit -q -m "Good file"
    
    # Modify and commit with bad content
    printf "Bad content: \xE2\x82\xAC\n" > file.txt
    git add file.txt
    git commit -q -m "Bad file"
    
    # Go back to first commit
    git checkout -q HEAD~1
    
    # Verify file has good content
    if grep -q "Original good content" file.txt; then
        pass_test "Working tree has correct content"
    else
        fail_test "Working tree content is wrong"
        return 1
    fi
    
    # Try to checkout bad commit - should fail
    git checkout HEAD 2>error.log || true
    
    # Verify original good content is still there (not corrupted)
    if grep -q "Original good content" file.txt; then
        pass_test "Working tree preserved after failed checkout"
    else
        fail_test "Working tree was corrupted by failed checkout"
        cat file.txt
        return 1
    fi
}

#
# Test 7: Verify error propagation in async mode (parallel checkout)
#
test_async_conversion_failure() {
    run_test "Async (parallel) checkout should handle encoding failures"
    
    cd "$TEST_DIR"
    rm -rf .git
    git init -q
    git config core.iconvtranslit false
    git config user.email "test@example.com"
    git config user.name "Test User"
    
    # Enable parallel checkout
    git config checkout.workers 2
    
    echo "*.txt working-tree-encoding=IBM-1047" > .gitattributes
    
    # Create multiple files, some with unconvertible content
    echo "Good file 1" > file1.txt
    echo "Good file 2" > file2.txt
    printf "Bad file: \xE2\x82\xAC\n" > file3.txt
    echo "Good file 4" > file4.txt
    
    git add .gitattributes file*.txt
    git commit -q -m "Mixed files"
    
    # Remove files
    rm -f file*.txt
    
    # Try checkout - should fail
    if git checkout HEAD -- . 2>async_error.log; then
        fail_test "Async checkout should have failed"
        cat async_error.log
        return 1
    fi
    
    if grep -q "failed to convert" async_error.log; then
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
    log_info "======================================"
    
    setup_repo
    
    test_unconvertible_character
    test_convertible_character
    test_full_checkout_abort
    test_clone_encoding_failure
    test_branch_switch_encoding_failure
    test_no_corruption_on_failure
    test_async_conversion_failure
    
    echo ""
    log_info "======================================"
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
