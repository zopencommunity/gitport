#!/bin/sh
mydir=$(cd $(dirname $0) && echo $PWD)

#
# The following is a bit hokey... might not always work
#
gitdir="${mydir}/../git-*"
if ! [ -d ${gitdir} ] ; then
  echo "Unable to find git dev driver" >&2
  exit 99
fi
absgitdir=$(cd ${gitdir} && echo $PWD)

#
# First, clean up the environment
#
  unset GIT_EXEC_PATH
  unset GIT_HOME
  unset GIT_MAN_PATH
  unset GIT_PAGER
  unset GIT_ROOT
  unset GIT_SHELL
  unset GIT_SSL_CAINFO
  unset GIT_TEMPLATE_DIR

  export PATH=/bin:/usr/bin:${absgitdir}
  unset LIBPATH

  export GIT_CONFIG_NOSYSTEM

  tmpdir="/tmp/git-$$"
  mkdir "${tmpdir}" || exit 99             
  cd "${tmpdir}" || exit 99
  touch ".gitconfig" || exit 99

  export GIT_TEMPLATE_DIR='/fultonm/zopen/dev/gitport/git-2.9.5/templates/blt'  

  if git clone git@github.com:ZOSOpenTools/zotsampleport.git >gitclone.out 2>gitclone.err ; then
    echo "Test passed"
    exit 0
  else
    echo "git clone failed" >&2
    echo "See $tmpdir/gitclone.* for results" >&2
    exit 4
  fi
  
