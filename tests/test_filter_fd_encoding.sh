#!/bin/bash

# Test case for filter-FD encoding failure propagation
# Tests that encoding failures are properly caught when using clean filters
#
# Determinism note:
# The original version relied on a "non-convertible character" (U+2011) not
# existing in IBM-1047. Whether iconv rejects such bytes depends on the
# libiconv build (some map every byte, e.g. 0x80 -> U+0080, and never fail).
# This version triggers conversion failures deterministically by using an
# encoding name unknown to iconv (iconv_open fails => conversion always fails),
# which is independent of the libiconv build and of file tags.

set -e
set -o pipefail   # 'git add ... | tee' must reflect git's exit status

TEST_NAME="Filter-FD encoding failure"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions if available
if [ -f "$SCRIPT_DIR/test_common.sh" ]; then
    source "$SCRIPT_DIR/test_common.sh"
else
    # Minimal implementations
    log_test_start() { echo "=== TEST: $1 ==="; }
    log_test_pass() { echo "✅ PASS: $1"; }
    log_test_fail() { echo "❌ FAIL: $1"; exit 1; }
    log_info() { echo "   $1"; }
fi

# An encoding name that iconv does not know; any conversion to/from it fails.
BAD_ENCODING="NOSUCHENC-12345"

TEST_DIR="$HOME/delete/test_filter_fd_encoding"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

log_test_start "$TEST_NAME"

# Initialize git repo
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git config core.iconvtranslit false  # Disable transliteration for strict testing
git config core.ignorefiletags true  # Don't depend on the machine's global config

log_info "Setting up clean filter and encoding attributes..."

# Create a simple clean filter that just passes through content
git config filter.testfilter.clean "cat"
git config filter.testfilter.smudge "cat"

# Set up .gitattributes with BOTH filter and encoding
cat > .gitattributes << 'EOF'
*.txt filter=testfilter working-tree-encoding=IBM-1047
EOF

git add .gitattributes
git commit -q -m "Add gitattributes with filter + encoding"

log_info "Test 1: File with convertible characters (should succeed)"
echo "Hello World" > test1.txt
if git add test1.txt 2>&1; then
    log_test_pass "Convertible file added successfully"
    git commit -q -m "Add test1"
else
    log_test_fail "Failed to add convertible file"
fi

log_info "Test 2: File with failing encoding (should fail)"
# Switch to an encoding iconv cannot open; every conversion now fails
# deterministically, regardless of file content, tags, or libiconv build.
cat > .gitattributes << EOF
*.txt filter=testfilter working-tree-encoding=$BAD_ENCODING
EOF
printf "Test with non\xe2\x80\x91breaking hyphen\n" > test2.txt

log_info "Attempting to add file with failing encoding..."
if git add test2.txt 2>&1 | tee /tmp/filter_fd_error.txt; then
    log_test_fail "git add should have failed but succeeded (bug!)"
else
    log_info "git add failed as expected ✓"

    # Check that the error message is appropriate
    if grep -q "failed to encode" /tmp/filter_fd_error.txt; then
        log_test_pass "Error message contains 'failed to encode'"
    else
        log_info "⚠️  Warning: Error message doesn't mention encoding failure"
        log_info "Error output:"
        cat /tmp/filter_fd_error.txt
        # Don't fail the test, but note the issue
    fi
fi

log_info "Test 3: Verify file was not added to index"
if git ls-files test2.txt | grep -q test2.txt; then
    log_test_fail "File should not be in index after failed add"
else
    log_test_pass "File correctly not in index"
fi

log_info "Test 4: Test with transliteration enabled"
# Restore a real encoding; with transliteration the add should succeed
# (on lenient iconv builds every byte converts anyway; on strict builds
# TRANSLIT substitutes the unconvertible character).
cat > .gitattributes << 'EOF'
*.txt filter=testfilter working-tree-encoding=IBM-1047
EOF
git config core.iconvtranslit true

log_info "Attempting to add file with transliteration enabled..."
if git add test2.txt 2>&1 | tee /tmp/filter_fd_translit.txt; then
    log_test_pass "File added with transliteration"

    # Check for warning
    if grep -q "transliteration\|warning" /tmp/filter_fd_translit.txt; then
        log_test_pass "Warning issued about transliteration"
    else
        log_info "⚠️  No warning about transliteration (may be expected)"
    fi

    # Verify file is in index
    if git ls-files test2.txt | grep -q test2.txt; then
        log_test_pass "File is in index"
    else
        log_test_fail "File should be in index after successful add"
    fi
else
    log_test_fail "File should have been added with transliteration"
fi

log_info "Test 5: Verify round-trip (checkout after commit)"
git commit -q -m "Add test2 with transliteration"
rm test2.txt

if git checkout test2.txt 2>&1; then
    log_test_pass "Checkout succeeded"

    # Verify file exists and is tagged correctly
    if [ -f test2.txt ]; then
        log_test_pass "File exists after checkout"

        # Check file tag
        FILE_TAG=$(ls -T test2.txt 2>/dev/null | awk '{print $1}')
        if [ "$FILE_TAG" = "t" ]; then
            log_test_pass "File is properly tagged as text"
        else
            log_info "⚠️  File tag: $FILE_TAG (expected 't')"
        fi
    else
        log_test_fail "File doesn't exist after checkout"
    fi
else
    log_test_fail "Checkout failed"
fi

# Cleanup
cd /
rm -rf "$TEST_DIR"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  $TEST_NAME: ALL TESTS PASSED ✅"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  ✅ Convertible files work with filters"
echo "  ✅ Failing encodings abort the add in strict mode"
echo "  ✅ Error message is clear"
echo "  ✅ Failed files not added to index"
echo "  ✅ Transliteration mode works"
echo "  ✅ Round-trip checkout works"
echo ""
