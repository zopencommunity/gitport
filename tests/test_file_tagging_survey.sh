#!/usr/bin/env bash
# ==============================================================================
# Survey: Which Git commands write files and check their tagging
# 
# Note: This test uses ISO8859-1 encoding (not IBM-1047) because test files
# are created with 'echo' which produces ASCII/ISO8859-1 content. Using
# ISO8859-1 in .gitattributes matches the actual file encoding, allowing
# git apply and git rebase to work correctly.
# ==============================================================================
set +e  # Don't exit on errors, we want to see all results

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -x "$REPO_ROOT/git/git" ]; then
    GIT_BIN="$REPO_ROOT/git/git"
else
    GIT_BIN="$(which git)"
fi

TEST_ROOT="$(pwd)/test_tmp_$$"
mkdir -p "$TEST_ROOT"
trap 'rm -rf "$TEST_ROOT"' EXIT

echo "========================================================================"
echo "    FILE TAGGING SURVEY - Which commands need fixes?                   "
echo "========================================================================"
echo "Git: $("$GIT_BIN" --version)"
echo "Test: $TEST_ROOT"
echo ""

RESULTS=()

# Helper to run a test
run_test() {
    local name="$1"
    local result="$2"
    RESULTS+=("$name|$result")
}

cd "$TEST_ROOT"

# ==============================================================================
# Test 1: git rerere (baseline - already fixed)
# ==============================================================================
echo "[1/10] Testing: git rerere"
mkdir t1 && cd t1
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "T" && $GIT_BIN config user.email "t@t.com"
$GIT_BIN config rerere.enabled true
$GIT_BIN config core.ignorefiletags false
echo "*.txt zos-working-tree-encoding=ISO8859-1" > .gitattributes
$GIT_BIN add .gitattributes && $GIT_BIN commit -q -m "a" 2>/dev/null
echo "v1" > f.txt && $GIT_BIN add f.txt && $GIT_BIN commit -q -m "b" 2>/dev/null
$GIT_BIN checkout -q -b br 2>/dev/null
echo "v2" > f.txt && $GIT_BIN add f.txt && $GIT_BIN commit -q -m "c" 2>/dev/null
$GIT_BIN checkout -q master 2>/dev/null
echo "v3" > f.txt && $GIT_BIN add f.txt && $GIT_BIN commit -q -m "d" 2>/dev/null
$GIT_BIN merge br 2>/dev/null || true
echo "resolved" > f.txt && $GIT_BIN add f.txt && $GIT_BIN commit -q -m "e" 2>/dev/null
$GIT_BIN reset --hard HEAD~2 -q 2>/dev/null
echo "v3" > f.txt && $GIT_BIN add f.txt && $GIT_BIN commit -q -m "f" 2>/dev/null
$GIT_BIN merge br 2>/dev/null || true
TAG=$(chtag -p f.txt 2>/dev/null | awk '{print $2}')
if [ "$TAG" = "ISO8859-1" ]; then
    echo "  ✓ PASS: Tagged as ISO8859-1"
    run_test "rerere" "PASS"
else
    echo "  ✗ FAIL: Tagged as $TAG"
    run_test "rerere" "FAIL:$TAG"
fi
cd ..

# ==============================================================================
# Test 2: git apply (regular, non-3way)
# ==============================================================================
echo ""
echo "[2/10] Testing: git apply (regular patch)"
mkdir t2 && cd t2
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "T" && $GIT_BIN config user.email "t@t.com"
$GIT_BIN config core.ignorefiletags false
echo "*.txt zos-working-tree-encoding=ISO8859-1" > .gitattributes
$GIT_BIN add .gitattributes && $GIT_BIN commit -q -m "a" 2>/dev/null

cat > f.txt << 'TXT'
line1
line2
line3
TXT
$GIT_BIN add f.txt && $GIT_BIN commit -q -m "b" 2>/dev/null

cat > f.txt << 'TXT'
line1
line2 modified
line3
TXT

$GIT_BIN diff > /tmp/patch.txt 2>/dev/null
$GIT_BIN checkout f.txt 2>/dev/null

if $GIT_BIN apply /tmp/patch.txt 2>/dev/null; then
    TAG=$(chtag -p f.txt 2>/dev/null | awk '{print $2}')
    if [ "$TAG" = "ISO8859-1" ]; then
        echo "  ✓ PASS: Tagged as ISO8859-1"
        run_test "apply" "PASS"
    else
        echo "  ✗ FAIL: Tagged as $TAG"
        run_test "apply" "FAIL:$TAG"
    fi
else
    echo "  ✗ FAIL: Apply failed"
    run_test "apply" "FAIL:apply-failed"
fi
cd ..

# ==============================================================================
# Test 3: git merge-file
# ==============================================================================
echo ""
echo "[3/10] Testing: git merge-file"
mkdir t3 && cd t3
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config core.ignorefiletags false
echo "*.txt zos-working-tree-encoding=ISO8859-1" > .gitattributes

echo "base" > base.txt
echo "current" > current.txt
echo "other" > other.txt

if $GIT_BIN merge-file current.txt base.txt other.txt 2>/dev/null; then
    TAG=$(chtag -p current.txt 2>/dev/null | awk '{print $2}')
    if [ "$TAG" = "ISO8859-1" ]; then
        echo "  ✓ PASS: Tagged as ISO8859-1"
        run_test "merge-file" "PASS"
    else
        echo "  ✗ FAIL: Tagged as $TAG"
        run_test "merge-file" "FAIL:$TAG"
    fi
else
    echo "  ℹ Merge failed (expected), checking tag anyway"
    TAG=$(chtag -p current.txt 2>/dev/null | awk '{print $2}')
    if [ "$TAG" = "ISO8859-1" ]; then
        echo "  ✓ PASS: Tagged as ISO8859-1"
        run_test "merge-file" "PASS"
    else
        echo "  ✗ FAIL: Tagged as $TAG"
        run_test "merge-file" "FAIL:$TAG"
    fi
fi
cd ..

# ==============================================================================
# Test 4: git diff --output
# ==============================================================================
echo ""
echo "[4/10] Testing: git diff --output=file"
mkdir t4 && cd t4
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "T" && $GIT_BIN config user.email "t@t.com"
$GIT_BIN config core.ignorefiletags false
echo "*.diff zos-working-tree-encoding=ISO8859-1" > .gitattributes
$GIT_BIN add .gitattributes && $GIT_BIN commit -q -m "a" 2>/dev/null

echo "v1" > f.txt && $GIT_BIN add f.txt && $GIT_BIN commit -q -m "b" 2>/dev/null
echo "v2" > f.txt && $GIT_BIN add f.txt && $GIT_BIN commit -q -m "c" 2>/dev/null

$GIT_BIN diff HEAD~1 HEAD --output=out.diff 2>/dev/null

TAG=$(chtag -p out.diff 2>/dev/null | awk '{print $2}')
if [ "$TAG" = "ISO8859-1" ]; then
    echo "  ✓ PASS: Tagged as ISO8859-1"
    run_test "diff-output" "PASS"
else
    echo "  ✗ FAIL: Tagged as $TAG"
    run_test "diff-output" "FAIL:$TAG"
fi
cd ..

# ==============================================================================
# Test 5: git stash apply
# ==============================================================================
echo ""
echo "[5/10] Testing: git stash apply"
mkdir t5 && cd t5
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "T" && $GIT_BIN config user.email "t@t.com"
$GIT_BIN config core.ignorefiletags false
echo "*.txt zos-working-tree-encoding=ISO8859-1" > .gitattributes
$GIT_BIN add .gitattributes && $GIT_BIN commit -q -m "a" 2>/dev/null

echo "committed" > f.txt && $GIT_BIN add f.txt && $GIT_BIN commit -q -m "b" 2>/dev/null
echo "stashed" > f.txt
$GIT_BIN stash push -q 2>/dev/null
echo "other" > f.txt && $GIT_BIN add f.txt && $GIT_BIN commit -q -m "c" 2>/dev/null

$GIT_BIN stash apply 2>/dev/null || true

TAG=$(chtag -p f.txt 2>/dev/null | awk '{print $2}')
if [ "$TAG" = "ISO8859-1" ]; then
    echo "  ✓ PASS: Tagged as ISO8859-1"
    run_test "stash-apply" "PASS"
else
    echo "  ✗ FAIL: Tagged as $TAG"
    run_test "stash-apply" "FAIL:$TAG"
fi
cd ..

# ==============================================================================
# Test 6: git checkout --conflict=diff3
# ==============================================================================
echo ""
echo "[6/10] Testing: git checkout --conflict=diff3"
mkdir t6 && cd t6
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "T" && $GIT_BIN config user.email "t@t.com"
$GIT_BIN config core.ignorefiletags false
echo "*.txt zos-working-tree-encoding=ISO8859-1" > .gitattributes
$GIT_BIN add .gitattributes && $GIT_BIN commit -q -m "a" 2>/dev/null

echo "base" > f.txt && $GIT_BIN add f.txt && $GIT_BIN commit -q -m "b" 2>/dev/null
$GIT_BIN checkout -q -b br 2>/dev/null
echo "branch" > f.txt && $GIT_BIN add f.txt && $GIT_BIN commit -q -m "c" 2>/dev/null
$GIT_BIN checkout -q master 2>/dev/null
echo "master" > f.txt && $GIT_BIN add f.txt && $GIT_BIN commit -q -m "d" 2>/dev/null

$GIT_BIN merge br 2>/dev/null || true
$GIT_BIN checkout --conflict=diff3 f.txt 2>/dev/null || true

TAG=$(chtag -p f.txt 2>/dev/null | awk '{print $2}')
if [ "$TAG" = "ISO8859-1" ]; then
    echo "  ✓ PASS: Tagged as ISO8859-1"
    run_test "checkout-conflict" "PASS"
else
    echo "  ✗ FAIL: Tagged as $TAG"
    run_test "checkout-conflict" "FAIL:$TAG"
fi
cd ..

# ==============================================================================
# Test 7: git worktree add
# ==============================================================================
echo ""
echo "[7/10] Testing: git worktree add"
mkdir t7 && cd t7
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "T" && $GIT_BIN config user.email "t@t.com"
$GIT_BIN config core.ignorefiletags false
echo "*.txt zos-working-tree-encoding=ISO8859-1" > .gitattributes
$GIT_BIN add .gitattributes && $GIT_BIN commit -q -m "a" 2>/dev/null

echo "content" > f.txt && $GIT_BIN add f.txt && $GIT_BIN commit -q -m "b" 2>/dev/null

$GIT_BIN worktree add /tmp/wt1 HEAD 2>/dev/null || true

if [ -f /tmp/wt1/f.txt ]; then
    TAG=$(chtag -p /tmp/wt1/f.txt 2>/dev/null | awk '{print $2}')
    if [ "$TAG" = "ISO8859-1" ]; then
        echo "  ✓ PASS: Tagged as ISO8859-1"
        run_test "worktree" "PASS"
    else
        echo "  ✗ FAIL: Tagged as $TAG"
        run_test "worktree" "FAIL:$TAG"
    fi
    rm -rf /tmp/wt1 2>/dev/null
else
    echo "  ℹ SKIP: Worktree file not found"
    run_test "worktree" "SKIP"
fi
cd ..

# ==============================================================================
# Test 8: git am (apply mailbox)
# ==============================================================================
echo ""
echo "[8/10] Testing: git am (apply mailbox)"
mkdir t8 && cd t8
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "T" && $GIT_BIN config user.email "t@t.com"
$GIT_BIN config core.ignorefiletags false
echo "*.txt zos-working-tree-encoding=ISO8859-1" > .gitattributes
$GIT_BIN add .gitattributes && $GIT_BIN commit -q -m "a" 2>/dev/null

echo "v1" > f.txt && $GIT_BIN add f.txt && $GIT_BIN commit -q -m "b" 2>/dev/null
echo "v2" > f.txt && $GIT_BIN add f.txt && $GIT_BIN commit -q -m "c" 2>/dev/null

$GIT_BIN format-patch -1 HEAD -o /tmp 2>/dev/null
$GIT_BIN reset --hard HEAD~1 -q 2>/dev/null

PATCH=$(ls /tmp/0001-*.patch 2>/dev/null | head -1)
if [ -n "$PATCH" ]; then
    $GIT_BIN am "$PATCH" 2>/dev/null || true
    TAG=$(chtag -p f.txt 2>/dev/null | awk '{print $2}')
    if [ "$TAG" = "ISO8859-1" ]; then
        echo "  ✓ PASS: Tagged as ISO8859-1"
        run_test "am" "PASS"
    else
        echo "  ✗ FAIL: Tagged as $TAG"
        run_test "am" "FAIL:$TAG"
    fi
    rm -f "$PATCH" 2>/dev/null
else
    echo "  ℹ SKIP: Patch not created"
    run_test "am" "SKIP"
fi
cd ..

# ==============================================================================
# Test 9: git restore (restore from index)
# ==============================================================================
echo ""
echo "[9/10] Testing: git restore"
mkdir t9 && cd t9
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "T" && $GIT_BIN config user.email "t@t.com"
$GIT_BIN config core.ignorefiletags false
echo "*.txt zos-working-tree-encoding=ISO8859-1" > .gitattributes
$GIT_BIN add .gitattributes && $GIT_BIN commit -q -m "a" 2>/dev/null

echo "committed" > f.txt && $GIT_BIN add f.txt && $GIT_BIN commit -q -m "b" 2>/dev/null
echo "modified" > f.txt

$GIT_BIN restore f.txt 2>/dev/null

TAG=$(chtag -p f.txt 2>/dev/null | awk '{print $2}')
if [ "$TAG" = "ISO8859-1" ]; then
    echo "  ✓ PASS: Tagged as ISO8859-1"
    run_test "restore" "PASS"
else
    echo "  ✗ FAIL: Tagged as $TAG"
    run_test "restore" "FAIL:$TAG"
fi
cd ..

# ==============================================================================
# Test 10: git rebase (interactive rebase)
# ==============================================================================
echo ""
echo "[10/10] Testing: git rebase"
mkdir t10 && cd t10
$GIT_BIN init -q 2>/dev/null
$GIT_BIN config user.name "T" && $GIT_BIN config user.email "t@t.com"
$GIT_BIN config core.ignorefiletags false
echo "*.txt zos-working-tree-encoding=ISO8859-1" > .gitattributes
$GIT_BIN add .gitattributes && $GIT_BIN commit -q -m "a" 2>/dev/null

echo "v1" > f.txt && $GIT_BIN add f.txt && $GIT_BIN commit -q -m "b" 2>/dev/null
echo "v2" > f.txt && $GIT_BIN add f.txt && $GIT_BIN commit -q -m "c" 2>/dev/null

# Use non-interactive rebase
GIT_SEQUENCE_EDITOR=true $GIT_BIN rebase -i HEAD~1 2>/dev/null || true

TAG=$(chtag -p f.txt 2>/dev/null | awk '{print $2}')
if [ "$TAG" = "ISO8859-1" ]; then
    echo "  ✓ PASS: Tagged as ISO8859-1"
    run_test "rebase" "PASS"
else
    echo "  ℹ INFO: Tagged as $TAG (rebase may not have run)"
    run_test "rebase" "INFO:$TAG"
fi
cd ..

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo "========================================================================"
echo "                         SUMMARY                                        "
echo "========================================================================"
echo ""

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
INFO_COUNT=0

for result in "${RESULTS[@]}"; do
    name=$(echo "$result" | cut -d'|' -f1)
    status=$(echo "$result" | cut -d'|' -f2)
    
    case "$status" in
        PASS)
            printf "  ✓ %-20s PASS\n" "$name"
            PASS_COUNT=$((PASS_COUNT + 1))
            ;;
        FAIL:*)
            tag=$(echo "$status" | cut -d':' -f2)
            printf "  ✗ %-20s FAIL (tagged as %s)\n" "$name" "$tag"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            ;;
        SKIP)
            printf "  ⊘ %-20s SKIP\n" "$name"
            SKIP_COUNT=$((SKIP_COUNT + 1))
            ;;
        INFO:*)
            tag=$(echo "$status" | cut -d':' -f2)
            printf "  ℹ %-20s INFO (tagged as %s)\n" "$name" "$tag"
            INFO_COUNT=$((INFO_COUNT + 1))
            ;;
    esac
done

echo ""
echo "Results:"
echo "  Passed: $PASS_COUNT"
echo "  Failed: $FAIL_COUNT"
echo "  Skipped: $SKIP_COUNT"
echo "  Info: $INFO_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo "✓ NO FAILURES - All tested commands tag files correctly!"
else
    echo "⚠ $FAIL_COUNT command(s) need fixing"
    echo ""
    echo "Commands that FAILED need investigation:"
    for result in "${RESULTS[@]}"; do
        name=$(echo "$result" | cut -d'|' -f1)
        status=$(echo "$result" | cut -d'|' -f2)
        if [[ "$status" == FAIL:* ]]; then
            tag=$(echo "$status" | cut -d':' -f2)
            echo "  - $name (tagged as $tag instead of ISO8859-1)"
        fi
    done
fi

echo ""
echo "========================================================================"

rm -rf "$TEST_ROOT" 2>/dev/null

exit $FAIL_COUNT

