#!/bin/bash
#
# Test: SSH known_hosts creation issue in scripts (NON-INTERACTIVE)
# Issue #165: git remote/ssh does not create ~/.ssh/known_hosts in scripts
#

set -e

echo "=========================================="
echo "Test: SSH known_hosts Creation Issue #165"
echo "(Non-interactive automated test)"
echo "=========================================="
echo

# Test configuration
TEST_HOST="github.com"
TEST_REPO="git@github.com:HarithaIBM/gitport.git"

# Create temporary SSH config for isolated testing
TEST_SSH_DIR="/tmp/test_ssh_$$"
mkdir -p "$TEST_SSH_DIR"

# Create minimal SSH config
cat > "$TEST_SSH_DIR/config" << EOF
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_rsa
EOF

echo "Test setup:"
echo "  Test SSH dir: $TEST_SSH_DIR"
echo "  Test host: $TEST_HOST"
echo "  Test repo: $TEST_REPO"
echo

echo "=========================================="
echo "Test 1: Check current known_hosts"
echo "=========================================="
echo

if [ -f ~/.ssh/known_hosts ]; then
    if grep -q "$TEST_HOST" ~/.ssh/known_hosts; then
        echo "✅ $TEST_HOST is in known_hosts (normal state)"
        BASELINE_EXISTS=true
    else
        echo "⚠️ $TEST_HOST NOT in known_hosts"
        BASELINE_EXISTS=false
    fi
else
    echo "⚠️ known_hosts does not exist"
    BASELINE_EXISTS=false
fi

echo
echo "=========================================="
echo "Test 2: Non-Interactive Script (the bug)"
echo "=========================================="
echo

# Create test script that simulates non-interactive environment
cat > "$TEST_SSH_DIR/test_script.sh" << 'SCRIPT_EOF'
#!/bin/bash
# This simulates running git in a script (like zigi does)

# Use a separate known_hosts file for testing
export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/tmp/test_known_hosts_$$"

echo "Running git ls-remote in script mode (non-interactive)..."
git ls-remote git@github.com:HarithaIBM/gitport.git HEAD 2>&1 | head -3
EXIT_CODE=${PIPESTATUS[0]}

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Git command succeeded"
else
    echo "❌ Git command failed with exit code: $EXIT_CODE"
fi

exit $EXIT_CODE
SCRIPT_EOF

chmod +x "$TEST_SSH_DIR/test_script.sh"

echo "Created test script (simulating zigi/automated workflow)"
echo

# Remove test known_hosts if it exists
rm -f /tmp/test_known_hosts_$$

echo "Running script in non-interactive mode..."
"$TEST_SSH_DIR/test_script.sh"
RESULT2=$?

echo
echo "Result: Exit code $RESULT2"
echo

if [ -f /tmp/test_known_hosts_$$ ]; then
    echo "✅ Test known_hosts was created"
    echo "Content:"
    cat /tmp/test_known_hosts_$$
else
    echo "❌ Test known_hosts was NOT created (THIS IS THE BUG)"
    echo "This is the issue reported in #165"
fi

rm -f /tmp/test_known_hosts_$$

echo
echo "=========================================="
echo "Test 3: Workaround - StrictHostKeyChecking=no"
echo "=========================================="
echo

rm -f /tmp/test_known_hosts_workaround_$$

cat > "$TEST_SSH_DIR/test_workaround.sh" << 'SCRIPT_EOF'
#!/bin/bash
export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/tmp/test_known_hosts_workaround_$$ -o StrictHostKeyChecking=no"
echo "Testing with StrictHostKeyChecking=no..."
git ls-remote git@github.com:HarithaIBM/gitport.git HEAD 2>&1 | head -3
exit ${PIPESTATUS[0]}
SCRIPT_EOF

chmod +x "$TEST_SSH_DIR/test_workaround.sh"

"$TEST_SSH_DIR/test_workaround.sh"
RESULT3=$?

echo
echo "Result: Exit code $RESULT3"

if [ $RESULT3 -eq 0 ]; then
    echo "✅ Workaround successful"
else
    echo "❌ Workaround failed"
fi

rm -f /tmp/test_known_hosts_workaround_$$

echo
echo "=========================================="
echo "Test 4: Workaround - Pre-populate with ssh-keyscan"
echo "=========================================="
echo

rm -f /tmp/test_known_hosts_keyscan_$$

echo "Pre-populating known_hosts with ssh-keyscan..."
ssh-keyscan -H $TEST_HOST 2>/dev/null > /tmp/test_known_hosts_keyscan_$$

if [ -s /tmp/test_known_hosts_keyscan_$$ ]; then
    echo "✅ ssh-keyscan succeeded"
    echo "Entries added:"
    cat /tmp/test_known_hosts_keyscan_$$ | wc -l
    
    # Test git with pre-populated known_hosts
    cat > "$TEST_SSH_DIR/test_keyscan.sh" << 'SCRIPT_EOF'
#!/bin/bash
export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/tmp/test_known_hosts_keyscan_$$"
git ls-remote git@github.com:HarithaIBM/gitport.git HEAD 2>&1 | head -3
exit ${PIPESTATUS[0]}
SCRIPT_EOF
    
    chmod +x "$TEST_SSH_DIR/test_keyscan.sh"
    "$TEST_SSH_DIR/test_keyscan.sh"
    RESULT4=$?
    
    echo
    if [ $RESULT4 -eq 0 ]; then
        echo "✅ Git works with pre-populated known_hosts"
    else
        echo "❌ Git failed even with pre-populated known_hosts"
    fi
else
    echo "❌ ssh-keyscan failed"
    RESULT4=1
fi

rm -f /tmp/test_known_hosts_keyscan_$$

echo
echo "=========================================="
echo "Test 5: Check SSH version"
echo "=========================================="
echo

SSH_VERSION=$(ssh -V 2>&1)
echo "SSH Version: $SSH_VERSION"
echo

if [[ "$SSH_VERSION" == *"OpenSSH_9"* ]] || [[ "$SSH_VERSION" == *"OpenSSH_9"* ]]; then
    echo "⚠️ OpenSSH 9.x or later detected"
    echo "User reports this issue started with OpenSSH 9"
    OPENSSH_9=true
else
    echo "ℹ️ OpenSSH version < 9"
    OPENSSH_9=false
fi

echo
echo "=========================================="
echo "Test 6: Workaround - StrictHostKeyChecking=accept-new"
echo "=========================================="
echo

rm -f /tmp/test_known_hosts_accept_$$

cat > "$TEST_SSH_DIR/test_accept_new.sh" << 'SCRIPT_EOF'
#!/bin/bash
export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/tmp/test_known_hosts_accept_$$ -o StrictHostKeyChecking=accept-new"
echo "Testing with StrictHostKeyChecking=accept-new..."
git ls-remote git@github.com:HarithaIBM/gitport.git HEAD 2>&1 | head -3
exit ${PIPESTATUS[0]}
SCRIPT_EOF

chmod +x "$TEST_SSH_DIR/test_accept_new.sh"

"$TEST_SSH_DIR/test_accept_new.sh"
RESULT6=$?

echo
echo "Result: Exit code $RESULT6"

if [ $RESULT6 -eq 0 ]; then
    echo "✅ accept-new workaround successful"
    if [ -f /tmp/test_known_hosts_accept_$$ ]; then
        echo "✅ known_hosts was created automatically"
        echo "This is the BEST workaround - automatic and secure"
    fi
else
    echo "❌ accept-new workaround failed"
fi

rm -f /tmp/test_known_hosts_accept_$$

echo
echo "=========================================="
echo "Summary"
echo "=========================================="
echo
echo "Issue #165: git remote/ssh does not create known_hosts in scripts"
echo
echo "Test 2 (Script without workaround):           Exit $RESULT2"
echo "Test 3 (StrictHostKeyChecking=no):            Exit $RESULT3"
echo "Test 4 (Pre-populate with ssh-keyscan):       Exit $RESULT4"
echo "Test 6 (StrictHostKeyChecking=accept-new):    Exit $RESULT6"
echo
echo "SSH Version: $SSH_VERSION"
echo

if [ "$BASELINE_EXISTS" = true ]; then
    echo "Note: $TEST_HOST already in known_hosts, so Test 2 may have passed"
    echo "      Remove $TEST_HOST from known_hosts to see the actual bug"
fi

echo
echo "=========================================="
echo "Recommended Workarounds for Scripts"
echo "=========================================="
echo
echo "Best: Use StrictHostKeyChecking=accept-new (OpenSSH 7.6+)"
echo "  export GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=accept-new'"
echo "  - Automatically adds new hosts"
echo "  - Rejects changed keys (secure)"
echo "  - No user prompt needed"
echo
echo "Alternative: Pre-populate known_hosts"
echo "  ssh-keyscan github.com >> ~/.ssh/known_hosts"
echo "  ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts"
echo
echo "Quick/Dirty: Disable checking (INSECURE)"
echo "  export GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no'"
echo "  - Not recommended for production"
echo "  - Vulnerable to MITM attacks"
echo

# Cleanup
rm -rf "$TEST_SSH_DIR"

echo
echo "Test complete"
echo

# Exit with error if any critical test failed
if [ $RESULT3 -ne 0 ] && [ $RESULT4 -ne 0 ] && [ $RESULT6 -ne 0 ]; then
    echo "❌ All workarounds failed - there may be a connectivity issue"
    exit 1
else
    echo "✅ At least one workaround succeeded"
    exit 0
fi
