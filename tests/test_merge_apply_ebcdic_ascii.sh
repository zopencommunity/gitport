#!/bin/bash
#
# Test: normal merge and apply (no rerere) with EBCDIC and ASCII files
#
# Complements test_rerere_ebcdic_replay.sh (rerere paths) and
# test_apply_ebcdic_plain.sh (plain apply). This test verifies BOTH the
# file tag and the content for plain, non-rerere operations:
#
#   1. clean merge (no conflict) with EBCDIC files
#   2. conflicted merge with manual resolution, EBCDIC file
#   3. clean merge with ASCII files
#   4. conflicted merge with manual resolution, ASCII file
#   5. plain git apply with EBCDIC file
#   6. plain git apply with ASCII file
#
# Content is verified via the hash-object round-trip: hash-object
# applies the worktree->git conversion, so the working file must hash
# to the same blob as the expected canonical content.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="${SCRIPT_DIR}/test_merge_apply_ebcdic_ascii_$$"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

cleanup() {
    if [ -d "$TEST_DIR" ]; then
        cd "$SCRIPT_DIR"
        rm -rf "$TEST_DIR"
    fi
}

trap cleanup EXIT

log_info()    { echo -e "${YELLOW}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $1"; }

run_test()  { TESTS_RUN=$((TESTS_RUN + 1)); log_info "Running test $TESTS_RUN: $1"; }
pass_test() { TESTS_PASSED=$((TESTS_PASSED + 1)); log_success "$1"; }
fail_test() { TESTS_FAILED=$((TESTS_FAILED + 1)); log_error "$1"; }

# Create a file with genuine EBCDIC content, tagged IBM-1047.
write_ebcdic_file() {
    local file="$1" content="$2"
    touch "$file"
    chtag -tc 1047 "$file"
    printf '%s\n' "$content" > "$file"
}

# Verify the tag of a working file.
check_tag() {
    local file="$1" tag="$2"
    if chtag -p "$file" 2>/dev/null | grep -q "$tag"; then
        return 0
    fi
    fail_test "$file is not tagged $tag (got: $(chtag -p "$file" 2>/dev/null))"
    return 1
}

# Verify the canonical content of a working file via hash-object.
check_content() {
    local file="$1" expected="$2"
    local expected_blob actual_blob
    expected_blob=$(printf '%s\n' "$expected" | git hash-object --stdin)
    actual_blob=$(git hash-object "$file")
    if [ "$expected_blob" != "$actual_blob" ]; then
        fail_test "$file content does not match the expected canonical form"
        return 1
    fi
    return 0
}

setup_repo() {
    local dir="$1" attrs="$2"
    cd "$TEST_DIR"
    rm -rf "$dir"
    mkdir "$dir"
    cd "$dir"
    git init -q -b main
    git config user.email "test@example.com"
    git config user.name "Test User"
    git config core.ignorefiletags true
    printf '%s\n' "$attrs" > .gitattributes
}

#
# Test 1: clean merge (no conflict) with EBCDIC files
#
test_clean_merge_ebcdic() {
    run_test "clean merge with EBCDIC files"

    setup_repo t1 "* zos-working-tree-encoding=ibm-1047
.gitattributes zos-working-tree-encoding=iso8859-1"

    write_ebcdic_file a.txt "shared header
alpha line"
    write_ebcdic_file b.txt "shared header
beta line"
    git add .gitattributes a.txt b.txt
    git commit -q -m base

    git checkout -q -b topic
    write_ebcdic_file a.txt "shared header
topic changed alpha"
    git commit -qam topic

    git checkout -q main
    write_ebcdic_file b.txt "shared header
main changed beta"
    git commit -qam main

    if ! git merge topic >/dev/null 2>&1; then
        fail_test "clean merge failed"
        return 1
    fi

    check_tag a.txt "IBM-1047" || return 1
    check_tag b.txt "IBM-1047" || return 1
    pass_test "merged files tagged IBM-1047"

    check_content a.txt "shared header
topic changed alpha" || return 1
    check_content b.txt "shared header
main changed beta" || return 1
    pass_test "merged content correct (both sides' changes present)"

    git status --porcelain | grep -q . && { fail_test "worktree not clean after merge"; return 1; }
    return 0
}

#
# Test 2: conflicted merge with manual resolution, EBCDIC file
#
test_conflicted_merge_ebcdic() {
    run_test "conflicted merge with EBCDIC file"

    setup_repo t2 "* zos-working-tree-encoding=ibm-1047
.gitattributes zos-working-tree-encoding=iso8859-1"

    write_ebcdic_file c.txt "common
original"
    git add .gitattributes c.txt
    git commit -q -m base

    git checkout -q -b topic
    write_ebcdic_file c.txt "common
topic version"
    git commit -qam topic

    git checkout -q main
    write_ebcdic_file c.txt "common
main version"
    git commit -qam main

    if git merge topic >/dev/null 2>&1; then
        fail_test "merge should have conflicted"
        return 1
    fi

    # During the conflict: tag preserved and both sides readable
    check_tag c.txt "IBM-1047" || return 1
    if ! grep -q "main version" c.txt || ! grep -q "topic version" c.txt; then
        fail_test "conflict sides not readable in the conflicted file"
        return 1
    fi
    pass_test "conflicted file tagged IBM-1047 with readable conflict sides"

    # Manual resolution
    write_ebcdic_file c.txt "common
manually resolved"
    git add c.txt
    git commit -q -m "merge topic" >/dev/null

    check_tag c.txt "IBM-1047" || return 1
    check_content c.txt "common
manually resolved" || return 1
    pass_test "resolved file tagged IBM-1047 with correct content"
    return 0
}

#
# Test 3: clean merge with ASCII files
#
test_clean_merge_ascii() {
    run_test "clean merge with ASCII files"

    setup_repo t3 "* text
.gitattributes -text"

    printf 'shared header\nalpha line\n' > a.txt
    printf 'shared header\nbeta line\n' > b.txt
    git add .gitattributes a.txt b.txt
    git commit -q -m base

    git checkout -q -b topic
    printf 'shared header\ntopic changed alpha\n' > a.txt
    git commit -qam topic

    git checkout -q main
    printf 'shared header\nmain changed beta\n' > b.txt
    git commit -qam main

    if ! git merge topic >/dev/null 2>&1; then
        fail_test "clean merge failed"
        return 1
    fi

    check_content a.txt "shared header
topic changed alpha" || return 1
    check_content b.txt "shared header
main changed beta" || return 1
    pass_test "merged ASCII content correct (both sides' changes present)"
    return 0
}

#
# Test 4: conflicted merge with manual resolution, ASCII file
#
test_conflicted_merge_ascii() {
    run_test "conflicted merge with ASCII file"

    setup_repo t4 "* text
.gitattributes -text"

    printf 'common\noriginal\n' > c.txt
    git add .gitattributes c.txt
    git commit -q -m base

    git checkout -q -b topic
    printf 'common\ntopic version\n' > c.txt
    git commit -qam topic

    git checkout -q main
    printf 'common\nmain version\n' > c.txt
    git commit -qam main

    if git merge topic >/dev/null 2>&1; then
        fail_test "merge should have conflicted"
        return 1
    fi

    if ! grep -q "main version" c.txt || ! grep -q "topic version" c.txt; then
        fail_test "conflict sides not readable in the conflicted file"
        return 1
    fi

    printf 'common\nmanually resolved\n' > c.txt
    git add c.txt
    git commit -q -m "merge topic" >/dev/null

    check_content c.txt "common
manually resolved" || return 1
    pass_test "resolved ASCII content correct"
    return 0
}

#
# Test 5: plain git apply with EBCDIC file
#
test_apply_ebcdic() {
    run_test "plain git apply with EBCDIC file"

    setup_repo t5 "* zos-working-tree-encoding=ibm-1047
.gitattributes zos-working-tree-encoding=iso8859-1"

    write_ebcdic_file f.txt "hello world"
    git add .gitattributes f.txt
    git commit -q -m base

    write_ebcdic_file f.txt "hello world
apply modified"
    git diff > changes.patch
    git checkout -- f.txt

    if ! git apply changes.patch 2>apply.err; then
        fail_test "plain git apply failed on EBCDIC file"
        cat apply.err
        return 1
    fi

    check_tag f.txt "IBM-1047" || return 1
    check_content f.txt "hello world
apply modified" || return 1
    pass_test "applied EBCDIC file tagged IBM-1047 with correct content"
    return 0
}

#
# Test 6: plain git apply with ASCII file
#
test_apply_ascii() {
    run_test "plain git apply with ASCII file"

    setup_repo t6 "* text
.gitattributes -text"

    printf 'hello world\n' > f.txt
    git add .gitattributes f.txt
    git commit -q -m base

    printf 'hello world\napply modified\n' > f.txt
    git diff > changes.patch
    git checkout -- f.txt

    if ! git apply changes.patch 2>apply.err; then
        fail_test "plain git apply failed on ASCII file"
        cat apply.err
        return 1
    fi

    check_content f.txt "hello world
apply modified" || return 1
    pass_test "applied ASCII content correct"
    return 0
}

main() {
    log_info "Normal merge and apply with EBCDIC and ASCII files"
    log_info "===================================================="

    mkdir -p "$TEST_DIR"

    test_clean_merge_ebcdic
    test_conflicted_merge_ebcdic
    test_clean_merge_ascii
    test_conflicted_merge_ascii
    test_apply_ebcdic
    test_apply_ascii

    echo ""
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
