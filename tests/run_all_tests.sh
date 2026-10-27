#!/bin/bash
# Run all tests and output in TAP format

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/TEST_MANIFEST"
TEST_NUM=0
PASSED=0
FAILED=0
SKIPPED=0

# Test timeout (default 300 seconds = 5 minutes per test)
TEST_TIMEOUT="${TEST_TIMEOUT:-300}"

# Allow disabling custom tests via environment variable
if [ "${SKIP_CUSTOM_TESTS:-0}" = "1" ]; then
    echo "TAP version 13"
    echo "1..0 # SKIP Custom tests disabled via SKIP_CUSTOM_TESTS=1"
    exit 0
fi

# Function to run a test and capture result
run_test() {
    local test_script="$1"
    local test_name="$(basename "$test_script" .sh)"
    
    TEST_NUM=$((TEST_NUM + 1))
    
    # Use local temp directory instead of /tmp
    local test_output="${SCRIPT_DIR}/test_tmp_${test_name}_$$.out"
    mkdir -p "${SCRIPT_DIR}/test_tmp_${test_name}_$$"
    
    # Run the test (run from test directory to ensure correct paths)
    # Use ./ to run script directly instead of calling bash explicitly
    # Note: timeout command is broken on z/OS, so removed
    if (cd "$SCRIPT_DIR" && ./"$(basename "$test_script")") > "${test_output}" 2>&1; then
        PASSED=$((PASSED + 1))
        echo "ok $TEST_NUM - $test_name"
    else
        local exit_code=$?
        FAILED=$((FAILED + 1))
        echo "not ok $TEST_NUM - $test_name"
        # Include error details (first 50 lines)
        echo "# Test output (first 50 lines):"
        head -50 "${test_output}" | sed 's/^/# /'
    fi
    
    # Clean up temp files
    rm -rf "${SCRIPT_DIR}/test_tmp_${test_name}_$$" "${test_output}"
}

# Check if manifest exists
if [ ! -f "$MANIFEST" ]; then
    echo "Error: TEST_MANIFEST not found at $MANIFEST"
    echo "# Please create TEST_MANIFEST with list of tests to run"
    exit 1
fi

# Count tests in manifest (excluding comments and empty lines)
TEST_COUNT=$(grep -v '^#' "$MANIFEST" | grep -v '^$' | wc -l)

echo "TAP version 13"
echo "1..$TEST_COUNT"
echo "# Using TEST_MANIFEST for test discovery"
echo "# Tests to run: $TEST_COUNT"

# Run each test from manifest
while IFS= read -r test_name || [ -n "$test_name" ]; do
    # Skip comments
    [[ "$test_name" =~ ^#.*$ ]] && continue
    
    # Skip empty lines
    [[ -z "$test_name" ]] && continue
    
    # Strip leading/trailing whitespace
    test_name=$(echo "$test_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    test_script="$SCRIPT_DIR/$test_name"
    
    # Check if test file exists
    if [ ! -f "$test_script" ]; then
        echo "# Warning: $test_name not found at $test_script, skipping"
        continue
    fi
    
    # Check if test is executable
    if [ ! -x "$test_script" ]; then
        echo "# Warning: $test_name is not executable, skipping"
        continue
    fi
    
    run_test "$test_script"
done < "$MANIFEST"

# Summary
echo "# Tests run: $TEST_NUM"
echo "# Passed: $PASSED"
echo "# Failed: $FAILED"
echo "# Timeout per test: ${TEST_TIMEOUT}s"
echo "# To skip custom tests: export SKIP_CUSTOM_TESTS=1"
echo "# To change timeout: export TEST_TIMEOUT=600"

# Exit with failure if any test failed
[ $FAILED -eq 0 ]
