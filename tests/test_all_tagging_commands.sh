#!/usr/bin/env bash
# ==============================================================================
# Comprehensive test for all Git commands that write to working tree
# Tests: merge-file, diff --output, apply, rebase
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================================"
echo "         COMPREHENSIVE FILE TAGGING TEST SUITE                         "
echo "========================================================================"
echo ""

TOTAL_PASSED=0
TOTAL_TESTS=0
FAILURES=""

run_test() {
    local test_name="$1"
    local test_script="$2"
    
    echo "========================================================================"
    echo "  Running: $test_name"
    echo "========================================================================"
    
    if bash "$SCRIPT_DIR/$test_script"; then
        echo ""
        echo "✓ $test_name PASSED"
        echo ""
    else
        EXIT_CODE=$?
        echo ""
        echo "✗ $test_name FAILED (exit code: $EXIT_CODE)"
        echo ""
        FAILURES="${FAILURES}  - $test_name\n"
    fi
}

# Run all tests
run_test "merge-file and diff --output" "test_merge_file_diff_output.sh"
run_test "git apply" "test_apply_tagging.sh"
run_test "git rebase" "test_rebase_tagging.sh"

echo "========================================================================"
echo "                     FINAL SUMMARY                                      "
echo "========================================================================"
echo ""

if [ -z "$FAILURES" ]; then
    echo "  ✓✓✓ ALL TEST SUITES PASSED! ✓✓✓"
    echo ""
    echo "  Commands tested:"
    echo "    ✓ git merge-file"
    echo "    ✓ git diff --output"
    echo "    ✓ git apply"
    echo "    ✓ git rebase"
    echo ""
    echo "  All commands correctly tag files according to .gitattributes"
    exit 0
else
    echo "  ✗ SOME TEST SUITES FAILED:"
    echo ""
    echo -e "$FAILURES"
    echo ""
    echo "  Please check the output above for details"
    exit 1
fi
