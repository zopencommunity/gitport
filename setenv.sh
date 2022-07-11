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
export PORT_GIT_DEPS="git make m4 perl autoconf automake help2man makeinfo xz zlib openssl curl expat gettext"

export PORT_EXTRA_CPPFLAGS="-I\${OPENSSL_HOME}/include,\${GETTEXT_HOME}/include -DNO_REGEX=NeedsStartEnd"
export PORT_EXTRA_LDFLAGS="-L\${GETTEXT_HOME}/lib -L\${OPENSSL_HOME}/lib"

export PORT_BOOTSTRAP="make"
export PORT_BOOTSTRAP_OPTS="configure"
