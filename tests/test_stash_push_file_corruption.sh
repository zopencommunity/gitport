#!/bin/bash
#
# Test: git stash push <file> content corruption (z/OS encoding issue)
#
# Issue (reported against zopencommunity/gitport):
#   After 'git stash push zosGen/src/igyvcntl.plx', git reports success:
#       Saved working directory and index state WIP on ...
#       <stdin>:95: trailing whitespace.
#       warning: 1 line adds whitespace errors.
#   but the file left in the working tree is corrupted. The user notes:
#     - 'git stash' (whole tree) works fine
#     - 'git stash pop' restores the file perfectly
#     - so the bug is specific to 'git stash push <pathspec>'
#     - the restored file is encoded IBM-1047 but TAGGED ISO8859-1;
#       retagging makes it readable
#   .gitattributes rule for the file:
#       cobfe/zosGen/src/* zos-working-tree-encoding=ibm-1047
#
# This test verifies:
#   1. 'git stash push <file>' restores the HEAD version with the correct
#      IBM-1047 tag (not the default ISO8859-1)
#   2. The restored file CONTENT matches the index (no corruption) --
#      checked via git status, which compares real content, independent of
#      tags (grep/cat are unreliable on tagged EBCDIC files)
#   3. 'git stash pop' then restores the modified content intact,
#      byte-for-byte, with the correct tag
#   4. Lines with trailing whitespace survive the stash push/pop round-trip
#      (the <stdin>:N trailing-whitespace warning scenario)
#   5. Baseline: 'git stash' without a pathspec behaves correctly
#
# TAP format output for integration with zopen_check_results

if [ "$(uname)" != "OS/390" ]; then
    echo "1..0 # SKIP Not running on z/OS"
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Prefer in-tree build, fall back to PATH (what CI uses)
if [ -x "$SCRIPT_DIR/../git/git" ]; then
    GIT_BIN="$SCRIPT_DIR/../git/git"
else
    GIT_BIN="git"
fi

TEST_ROOT="$SCRIPT_DIR/test_tmp_stash_push_file_$$"
mkdir -p "$TEST_ROOT"
trap 'cd "$SCRIPT_DIR" && rm -rf "$TEST_ROOT"' EXIT

echo "TAP version 13"
echo "1..8"

TEST_NUM=0
FAIL_COUNT=0

tap() {
    # tap ok|not_ok "description" ["diagnostic"]
    TEST_NUM=$((TEST_NUM + 1))
    if [ "$1" = "ok" ]; then
        echo "ok $TEST_NUM - $2"
    else
        echo "not ok $TEST_NUM - $2"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        [ -n "$3" ] && echo "  # $3"
    fi
}

FILE="cobfe/zosGen/src/igyvcntl.plx"

make_repo() {
    cd "$TEST_ROOT"
    rm -rf repo && mkdir repo && cd repo
    "$GIT_BIN" init -q -b main 2>/dev/null
    "$GIT_BIN" config user.name "Test"
    "$GIT_BIN" config user.email "test@test.com"
    "$GIT_BIN" config core.ignorefiletags false
    "$GIT_BIN" config core.iconvtranslit false

    # .gitattributes exactly as in the reported issue
    mkdir -p cobfe/zosGen/src
    echo "cobfe/zosGen/src/* zos-working-tree-encoding=ibm-1047" > .gitattributes

    # COBOL-ish content resembling igyvcntl.plx, including a line with
    # trailing whitespace (the <stdin>:95 scenario)
    cat > head.txt << 'EOF'
       IDENTIFICATION DIVISION.
       PROGRAM-ID. TESTPROG.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
EOF
    iconv -f ISO8859-1 -t IBM-1047 < head.txt > "$FILE"
    rm head.txt
    chtag -tc 1047 "$FILE"

    "$GIT_BIN" add .gitattributes "$FILE" 2>/dev/null
    "$GIT_BIN" commit -q -m "Initial commit" 2>/dev/null
}

modify_file() {
    # Append modified content; last line has trailing whitespace
    cat > mod.txt << 'EOF'
       01  WS-VAR PIC X(10).
       01  WS-VAR2 PIC X(20).
       01  WS-TAGGED PIC X(4). VALUE 'ABCD'.
EOF
    # add trailing spaces on a line to trigger whitespace-error path
    printf '       01  WS-TRAIL.       \n' >> mod.txt
    iconv -f ISO8859-1 -t IBM-1047 < mod.txt >> "$FILE"
    rm mod.txt
    chtag -tc 1047 "$FILE"
}

tag_of() {
    chtag -p "$1" 2>/dev/null | awk '{print $2}'
}

########################################################################
# Tests 1-3: git stash push <file> -- tag and content after push
########################################################################
make_repo
modify_file

# Save the modified content for the later pop comparison (raw bytes)
cp "$FILE" "$TEST_ROOT/modified-snapshot.plx"
MOD_SHA_BEFORE=$(git hash-object "$FILE")

STASH_OUT=$("$GIT_BIN" stash push "$FILE" 2>&1)
STASH_RC=$?

if [ $STASH_RC -eq 0 ]; then
    tap ok "git stash push <file> exits 0"
else
    tap not_ok "git stash push <file> exits 0" "exit=$STASH_RC output: $STASH_OUT"
fi

# Test 2: file must be tagged IBM-1047 after stash push (the reported bug:
# EBCDIC content tagged ISO8859-1)
TAG=$(tag_of "$FILE")
if [ "$TAG" = "IBM-1047" ]; then
    tap ok "file tag after stash push is IBM-1047"
else
    tap not_ok "file tag after stash push is IBM-1047" "got: '$TAG' (expected IBM-1047)"
fi

# Test 3: restored content must match the index (HEAD version) -- this is
# the "corruption" check. git status compares real content after conversion,
# independent of the file tag.
ST=$(git status --porcelain "$FILE" 2>/dev/null)
if [ -z "$ST" ]; then
    tap ok "file content after stash push matches index (not corrupted)"
else
    tap not_ok "file content after stash push matches index (not corrupted)" "git status: $ST"
fi

########################################################################
# Tests 4-5: git stash pop restores modified content intact
########################################################################
POP_OUT=$("$GIT_BIN" stash pop 2>&1)
POP_RC=$?

TAG=$(tag_of "$FILE")
if [ "$TAG" = "IBM-1047" ]; then
    tap ok "file tag after stash pop is IBM-1047"
else
    tap not_ok "file tag after stash pop is IBM-1047" "got: '$TAG'"
fi

# Byte-for-byte comparison with the pre-stash snapshot (cmp reads raw
# bytes; both files tagged the same so no conversion interference)
if cmp -s "$FILE" "$TEST_ROOT/modified-snapshot.plx"; then
    tap ok "stash pop restores modified content byte-for-byte"
else
    tap not_ok "stash pop restores modified content byte-for-byte" \
        "content differs from pre-stash snapshot (rc=$POP_RC)"
fi

# Content-hash check as a second, tag-independent verification
MOD_SHA_AFTER=$(git hash-object "$FILE")
if [ "$MOD_SHA_BEFORE" = "$MOD_SHA_AFTER" ]; then
    tap ok "blob hash round-trips through stash push/pop"
else
    tap not_ok "blob hash round-trips through stash push/pop" \
        "before: $MOD_SHA_BEFORE after: $MOD_SHA_AFTER"
fi

########################################################################
# Test 6-7: baseline -- plain 'git stash' (no pathspec)
########################################################################
make_repo
modify_file

STASH_OUT=$("$GIT_BIN" stash 2>&1)
STASH_RC=$?

TAG=$(tag_of "$FILE")
if [ "$TAG" = "IBM-1047" ] && [ $STASH_RC -eq 0 ]; then
    tap ok "git stash (no pathspec) preserves IBM-1047 tag"
else
    tap not_ok "git stash (no pathspec) preserves IBM-1047 tag" \
        "rc=$STASH_RC tag='$TAG'"
fi

"$GIT_BIN" stash pop -q 2>/dev/null
if cmp -s "$FILE" "$TEST_ROOT/modified-snapshot.plx"; then
    tap ok "git stash (no pathspec) round-trip preserves content"
else
    tap not_ok "git stash (no pathspec) round-trip preserves content"
fi

echo "# Tests run: $TEST_NUM, failures: $FAIL_COUNT"
exit $FAIL_COUNT
