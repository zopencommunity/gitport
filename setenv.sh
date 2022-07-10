#!/bin/sh
#
# Set up environment variables for general build tool to operate
#
if ! [ -f ./setenv.sh ]; then
	echo "Need to source from the setenv.sh directory" >&2
	return 0
fi

# Note: requires zlib to be installed into system as pre-req
export PORT_ROOT="${PWD}"
export PORT_TYPE="GIT"

export PORT_GIT_URL="https://github.com/git/git"
export PORT_GIT_DEPS="git make m4 perl autoconf automake help2man makeinfo xz zlib openssl curl expat wish gettext"

export PORT_EXTRA_CFLAGS=""
export PORT_EXTRA_LDFLAGS=""
