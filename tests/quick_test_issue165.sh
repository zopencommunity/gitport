#!/bin/bash
#
# Quick test for Issue #165: SSH known_hosts in scripts
# 30-second verification (NON-INTERACTIVE, SAFE - does NOT modify ~/.ssh/known_hosts)
#

echo "=========================================="
echo "Quick Test: Issue #165"
echo "SSH known_hosts in scripts"
echo "=========================================="
echo

# Use completely isolated test files
TEST_KNOWN_HOSTS="/tmp/test_known_hosts_issue165_$$"
TEST_REPO="git@github.com:HarithaIBM/gitport.git"

echo "⚠️  SAFE MODE: This test does NOT modify your ~/.ssh/known_hosts"
echo "    Using test file: $TEST_KNOWN_HOSTS"
echo

# Test 1: Without workaround (should fail if bug exists)
echo "Test 1: Script without workaround (simulates the bug)"
cat > /tmp/test_no_workaround_$$.sh << 'TESTSCRIPT'
#!/bin/bash
# Simulate script environment without known_hosts
export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/tmp/test_known_hosts_issue165_$$"
git ls-remote git@github.com:HarithaIBM/gitport.git HEAD >/dev/null 2>&1
exit $?
TESTSCRIPT

chmod +x /tmp/test_no_workaround_$$.sh
/tmp/test_no_workaround_$$.sh
RESULT1=$?

echo
if [ $RESULT1 -eq 0 ]; then
    echo "✅ Test 1 PASSED (no bug detected)"
    if [ -f "$TEST_KNOWN_HOSTS" ]; then
        echo "   known_hosts was created automatically"
    fi
else
    echo "❌ Test 1 FAILED (bug exists)"
    echo "   Git cannot connect without known_hosts in script mode"
    echo "   This is Issue #165"
fi

rm -f "$TEST_KNOWN_HOSTS"
echo

# Test 2: With workaround (should always work)
echo "Test 2: Script with workaround (StrictHostKeyChecking=accept-new)"
cat > /tmp/test_with_workaround_$$.sh << 'TESTSCRIPT'
#!/bin/bash
# Use workaround to bypass the issue
export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/tmp/test_known_hosts_issue165_$$ -o StrictHostKeyChecking=accept-new"
git ls-remote git@github.com:HarithaIBM/gitport.git HEAD >/dev/null 2>&1
exit $?
TESTSCRIPT

chmod +x /tmp/test_with_workaround_$$.sh
/tmp/test_with_workaround_$$.sh
RESULT2=$?

echo
if [ $RESULT2 -eq 0 ]; then
    echo "✅ Test 2 PASSED (workaround works)"
    if [ -f "$TEST_KNOWN_HOSTS" ]; then
        echo "   known_hosts was created by workaround"
        echo "   Entries: $(wc -l < "$TEST_KNOWN_HOSTS")"
    fi
else
    echo "❌ Test 2 FAILED (workaround doesn't work)"
    echo "   May be connectivity or SSH key issue"
fi

echo
echo "=========================================="
echo "Summary"
echo "=========================================="
echo
echo "OpenSSH Version: $(ssh -V 2>&1)"
echo

if [ $RESULT1 -ne 0 ] && [ $RESULT2 -eq 0 ]; then
    echo "❌ Issue #165 EXISTS on this system"
    echo "   - Scripts fail without workaround"
    echo "   - Workaround is needed"
    echo
    echo "RECOMMENDED SOLUTION:"
    echo "  export GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=accept-new'"
    EXIT_CODE=1
elif [ $RESULT1 -eq 0 ]; then
    echo "✅ Issue #165 does NOT exist on this system"
    echo "   - Scripts work without workaround"
    echo "   - No action needed"
    EXIT_CODE=0
else
    echo "⚠️  Both tests failed - may be connectivity issue"
    echo "   Check: SSH key setup, network connectivity"
    EXIT_CODE=2
fi

# Cleanup
rm -f /tmp/test_no_workaround_$$.sh
rm -f /tmp/test_with_workaround_$$.sh
rm -f "$TEST_KNOWN_HOSTS"

echo
echo "✅ Your ~/.ssh/known_hosts was NOT modified"
echo
echo "Test complete"
exit $EXIT_CODE
