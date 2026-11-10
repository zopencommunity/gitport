#!/bin/bash
#
# Test: plain (direct) git operations on EBCDIC working-tree files
#
# Regression test for: 'git apply changes.patch' failing with
#   error: patch failed: <file>:1
#   error: <file>: patch does not apply
# when the source file is IBM-1047 (zos-working-tree-encoding), while
# working fine for UTF-8 files.
#
# Root cause: read_old_data() in apply.c read the working-tree file with a
# tag-honoring read (auto-converting EBCDIC to the process codepage) and
# then convert_to_git() converted it a SECOND time, corrupting the
# preimage so the patch context no longer matched.
#
# 'git am' applies patches through the same plain-apply code path and was
# broken by the same bug, so it is covered here as well.
#
# The existing apply tests (test_apply_3way_*.sh) all use --3way, which
# reads the preimage from the blob and bypasses the broken path entirely -
# which is why this regression was not caught before.
#
# Scenarios covered (all on files with genuine EBCDIC content and tags,
# matching what '_ENCODE_FILE_NEW=IBM-1047 vim file' produces):
#   1. plain 'git apply' (no --3way/--index/--cached)
#   2. 'git am'
#   3. 'git grep' against the working-tree file
#   4. 'git hash-object' of the working-tree file matches the blob
#   5. plain 'git apply' on a UTF-8 file (control case)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="${SCRIPT_DIR}/test_apply_ebcdic_plain_$$"

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

# Create a file with genuine EBCDIC content, tagged IBM-1047 (what
# _ENCODE_FILE_NEW=IBM-1047 vim produces on z/OS).
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

    # Attribute pattern from the reported issue
    cat > .gitattributes <<'EOF'
# General default for all files
* zos-working-tree-encoding=ibm-1047

# Specific exceptions
.gitattributes zos-working-tree-encoding=iso8859-1
.gitignore zos-working-tree-encoding=iso8859-1
*.xml zos-working-tree-encoding=utf-8
EOF
}

#
# Test 1: plain 'git apply' on an EBCDIC working-tree file
#
test_plain_apply_ebcdic() {
    run_test "plain git apply with IBM-1047 working-tree file"

    setup_repo

    write_ebcdic_file sample.txt "hello world"
    write_ebcdic_file other.txt "unrelated content"
    git add .gitattributes sample.txt other.txt
    git commit -q -m "commit message 1"

    # Verify the setup: blob must be clean UTF-8
    if git cat-file blob HEAD:sample.txt | od -An -tx1 | tr -d ' \n' | grep -q "^68656c6c6f"; then
        :
    else
        fail_test "setup: blob is not UTF-8 ('hello' = 68 65 6c 6c 6f)"
        return 1
    fi

    # Modify, create the patch, restore
    write_ebcdic_file sample.txt "hello world
second line modified"
    git diff > changes.patch
    git checkout -- sample.txt

    # Plain git apply - the regression: used to fail with
    # "patch failed: sample.txt:1 / patch does not apply"
    if ! git apply changes.patch 2>apply.err; then
        fail_test "plain git apply failed on EBCDIC file"
        cat apply.err
        return 1
    fi
    pass_test "plain git apply succeeded on EBCDIC file"

    # The result must still be tagged IBM-1047
    if chtag -p sample.txt 2>/dev/null | grep -q "IBM-1047"; then
        pass_test "applied file still tagged IBM-1047"
    else
        fail_test "applied file lost its IBM-1047 tag"
        return 1
    fi

    # Content check without touching the file: hash-object applies the
    # worktree->git conversion, so it must equal the canonical blob of
    # the expected UTF-8 content.
    local expected_blob actual_blob
    expected_blob=$(printf 'hello world\nsecond line modified\n' | git hash-object --stdin)
    actual_blob=$(git hash-object sample.txt)
    if [ "$expected_blob" = "$actual_blob" ]; then
        pass_test "applied content converts back to the expected canonical form"
    else
        fail_test "applied content is wrong (expected blob $expected_blob, got $actual_blob)"
        return 1
    fi
}

#
# Test 2: 'git am' on an EBCDIC working-tree file (same plain-apply path)
#
test_am_ebcdic() {
    run_test "git am with IBM-1047 working-tree file"

    setup_repo

    write_ebcdic_file sample.txt "hello world"
    git add .gitattributes sample.txt
    git commit -q -m "commit message 1"

    write_ebcdic_file sample.txt "hello world
am modified"
    git commit -qam "modify via am"
    git format-patch -1 HEAD -o "$TEST_DIR/repo" >/dev/null
    git reset -q --hard HEAD~1

    if ! git am 0001-*.patch 2>am.err; then
        fail_test "git am failed on EBCDIC file"
        cat am.err
        git am --abort 2>/dev/null
        return 1
    fi
    pass_test "git am succeeded on EBCDIC file"

    local expected_blob actual_blob
    expected_blob=$(printf 'hello world\nam modified\n' | git hash-object --stdin)
    actual_blob=$(git hash-object sample.txt)
    if [ "$expected_blob" = "$actual_blob" ]; then
        pass_test "git am content converts back to the expected canonical form"
    else
        fail_test "git am content is wrong (expected blob $expected_blob, got $actual_blob)"
        return 1
    fi
}

#
# Test 3: 'git grep' against an EBCDIC working-tree file
#
test_grep_ebcdic() {
    run_test "git grep on IBM-1047 working-tree file"

    setup_repo

    write_ebcdic_file sample.txt "hello world
needle line"
    git add .gitattributes sample.txt
    git commit -q -m "commit message 1"

    if git grep -q "needle line" -- sample.txt 2>/dev/null; then
        pass_test "git grep finds text in EBCDIC working-tree file"
    else
        fail_test "git grep did not find text in EBCDIC working-tree file"
        return 1
    fi

    if git grep -q "not there at all" -- sample.txt 2>/dev/null; then
        fail_test "git grep matched text that is not in the file"
        return 1
    fi
    pass_test "git grep does not match absent text"
}

#
# Test 4: 'git hash-object' of an EBCDIC working-tree file matches the blob
#
test_hash_object_ebcdic() {
    run_test "git hash-object round-trip for IBM-1047 working-tree file"

    setup_repo

    write_ebcdic_file sample.txt "hello world"
    git add .gitattributes sample.txt
    git commit -q -m "commit message 1"

    local expected_blob actual_blob
    expected_blob=$(printf 'hello world\n' | git hash-object --stdin)
    actual_blob=$(git hash-object sample.txt)
    if [ "$expected_blob" = "$actual_blob" ]; then
        pass_test "hash-object of EBCDIC file equals canonical blob"
    else
        fail_test "hash-object mismatch (expected $expected_blob, got $actual_blob)"
        return 1
    fi
}

#
# Test 5: plain 'git apply' on a UTF-8 file (control case)
#
test_plain_apply_utf8() {
    run_test "plain git apply with UTF-8 working-tree file (control)"

    setup_repo

    echo "*.txt zos-working-tree-encoding=utf-8" > .gitattributes
    printf 'hello world\n' > sample.txt
    chtag -tc 1208 sample.txt 2>/dev/null || true
    git add .gitattributes sample.txt
    git commit -q -m "commit message 1"

    printf 'hello world\nutf8 modified\n' > sample.txt
    chtag -tc 1208 sample.txt 2>/dev/null || true
    git diff > changes.patch
    git checkout -- sample.txt

    if ! git apply changes.patch 2>apply.err; then
        fail_test "plain git apply failed on UTF-8 file"
        cat apply.err
        return 1
    fi

    local expected_blob actual_blob
    expected_blob=$(printf 'hello world\nutf8 modified\n' | git hash-object --stdin)
    actual_blob=$(git hash-object sample.txt)
    if [ "$expected_blob" = "$actual_blob" ]; then
        pass_test "plain git apply works on UTF-8 file with correct content"
    else
        fail_test "UTF-8 apply content is wrong (expected $expected_blob, got $actual_blob)"
        return 1
    fi
}

main() {
    log_info "Plain git operations on EBCDIC working-tree files"
    log_info "==================================================="

    mkdir -p "$TEST_DIR"

    test_plain_apply_ebcdic
    test_am_ebcdic
    test_grep_ebcdic
    test_hash_object_ebcdic
    test_plain_apply_utf8

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
