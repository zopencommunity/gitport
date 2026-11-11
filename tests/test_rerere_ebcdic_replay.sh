#!/bin/bash
#
# Test: rerere replay with genuine EBCDIC working-tree files
#
# Regression test for two related reports:
#   1. rerere auto-resolve ("Resolved ... using previous resolution")
#      produces a file whose content is in the wrong encoding:
#      the rr-cache postimage was stored as raw EBCDIC (copy_file of the
#      working file) while preimage/thisimage are canonical, so ll_merge
#      mixed encodings and wrote garbage into the working file.
#   2. cherry-pick with rerere: "resulting files are not encoded
#      properly; zos-working-tree-encoding not respected" - the replay
#      result (canonical) was written raw into the working file under an
#      IBM-1047 tag, so the tag looked right but the bytes were wrong.
#
# The existing rerere tests (t0084, test_rerere_cherry_pick_issue.sh)
# create files with shell heredocs (ASCII bytes) and/or only assert the
# file tag, which is why the content corruption was not caught.
#
# This test uses files with genuine EBCDIC content and IBM-1047 tags
# (what _ENCODE_FILE_NEW=IBM-1047 vim produces) and verifies BOTH the
# tag and the content after rerere replay.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="${SCRIPT_DIR}/test_rerere_ebcdic_replay_$$"

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

setup_repo() {
    cd "$TEST_DIR"
    rm -rf repo
    mkdir repo
    cd repo
    git init -q -b main
    git config user.email "test@example.com"
    git config user.name "Test User"
    git config core.ignorefiletags true
    git config rerere.enabled true
    echo "* zos-working-tree-encoding=ibm-1047" > .gitattributes
    echo ".gitattributes zos-working-tree-encoding=iso8859-1" >> .gitattributes
}

# Verify tag + canonical content of an EBCDIC working file.
# hash-object applies the worktree->git conversion, so it must equal
# the blob of the expected canonical (UTF-8) content.
check_ebcdic_file() {
    local file="$1" expected="$2"
    if ! chtag -p "$file" 2>/dev/null | grep -q "IBM-1047"; then
        fail_test "$file is not tagged IBM-1047"
        return 1
    fi
    local expected_blob actual_blob
    expected_blob=$(printf '%s\n' "$expected" | git hash-object --stdin)
    actual_blob=$(git hash-object "$file")
    if [ "$expected_blob" != "$actual_blob" ]; then
        fail_test "$file content does not convert to the expected canonical form"
        return 1
    fi
    return 0
}

#
# Test 1: rerere replay of a merge conflict (EBCDIC file)
#
test_rerere_merge_replay() {
    run_test "rerere replay of merge conflict with EBCDIC file"

    setup_repo

    write_ebcdic_file file.txt "common line
original"
    git add .gitattributes file.txt
    git commit -q -m base

    git checkout -q -b feat_a
    write_ebcdic_file file.txt "common line
feat_a change"
    git commit -qam a

    git checkout -q main
    write_ebcdic_file file.txt "common line
main change"
    git commit -qam main

    # Conflict; resolve; rerere records the resolution
    git checkout -q -b feat_b
    git merge feat_a >/dev/null 2>&1 || true
    write_ebcdic_file file.txt "common line
resolved"
    git add file.txt
    git commit -q -m resolve >/dev/null 2>&1

    # The recorded postimage must be canonical (like preimage/thisimage),
    # not raw EBCDIC.
    local postimage
    postimage=$(find .git/rr-cache -name postimage | head -1)
    if [ -n "$postimage" ] && chtag -p "$postimage" 2>/dev/null | grep -q "IBM-1047"; then
        fail_test "rr-cache postimage stored as raw EBCDIC (must be canonical)"
        return 1
    fi
    pass_test "rr-cache postimage stored in canonical form"

    # Recreate the same conflict; rerere must replay with correct
    # tag AND content.
    git reset -q --hard HEAD~1
    git merge feat_a 2>&1 | grep -q "Resolved 'file.txt' using previous resolution" || {
        fail_test "rerere did not replay the recorded resolution"
        return 1
    }
    pass_test "rerere replayed the recorded resolution"

    check_ebcdic_file file.txt "common line
resolved" || return 1
    pass_test "replayed file has IBM-1047 tag and correct content"
}

#
# Test 2: rerere replay of a cherry-pick conflict (EBCDIC file)
#
test_rerere_cherry_pick_replay() {
    run_test "rerere replay of cherry-pick conflict with EBCDIC file"

    setup_repo

    write_ebcdic_file file.txt "base line
conflict here"
    git add .gitattributes file.txt
    git commit -q -m base

    git checkout -q -b side
    write_ebcdic_file file.txt "base line
side resolved"
    git commit -qam side
    local pick_commit
    pick_commit=$(git rev-parse HEAD)

    git checkout -q main
    write_ebcdic_file file.txt "base line
main change"
    git commit -qam main

    # Cherry-pick conflicts; resolve; rerere records
    git cherry-pick "$pick_commit" >/dev/null 2>&1 || true
    write_ebcdic_file file.txt "base line
side resolved"
    git add file.txt
    if ! git cherry-pick --continue --no-edit >/dev/null 2>&1; then
        fail_test "cherry-pick --continue failed; cannot set up rerere state"
        git cherry-pick --abort 2>/dev/null
        return 1
    fi

    # Undo the cherry-pick; the tree is back at the conflicting state
    git reset -q --hard HEAD~1

    # Cherry-pick again; the same conflict recurs and rerere must
    # replay the recorded resolution. Require the rerere replay
    # diagnostic so a clean (non-conflicting) apply cannot pass
    # the test by accident.
    local replay_out
    replay_out=$(git cherry-pick "$pick_commit" 2>&1 || true)
    if ! echo "$replay_out" | grep -q "Resolved 'file.txt' using previous resolution"; then
        fail_test "rerere did not replay the recorded resolution"
        echo "$replay_out" | head -5
        git cherry-pick --abort 2>/dev/null
        return 1
    fi
    pass_test "rerere replayed the cherry-pick resolution"

    check_ebcdic_file file.txt "base line
side resolved" || return 1
    pass_test "replayed file has IBM-1047 tag and correct content"
}

main() {
    log_info "rerere replay with genuine EBCDIC files"
    log_info "========================================"

    mkdir -p "$TEST_DIR"

    test_rerere_merge_replay
    test_rerere_cherry_pick_replay

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
