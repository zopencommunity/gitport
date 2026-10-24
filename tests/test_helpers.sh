#!/bin/bash

# Shared helper functions for z/OS Git tests

# Get expected UTF-8 tag based on GIT_UTF8_CCSID environment variable
# Returns "ISO8859-1" if GIT_UTF8_CCSID=819, otherwise "UTF-8"
get_expected_utf8_tag() {
    if [ "${GIT_UTF8_CCSID}" = "819" ]; then
        echo "ISO8859-1"
    else
        echo "UTF-8"
    fi
}

# Check if a tag is the expected UTF-8 tag
# Usage: if is_expected_utf8_tag "$actual_tag"; then ...
# Returns 0 (true) if tag matches expected UTF-8 encoding
is_expected_utf8_tag() {
    local actual="$1"
    local expected=$(get_expected_utf8_tag)
    [ "$actual" = "$expected" ]
}

