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

  gitrepo="zotsampleport"
  gitrepourl="git@github.com:ZOSOpenTools/${gitrepo}.git"
  main="main"

  if ! mkdir "${gitrepo}" ; then
    echo "Unable to create ${gitrepo} directory" >&2
    exit 99
  fi

  if ! cd "${gitrepo}" ; then
    echo "Unable to cd into ${gitrepo} directory" >&2
    exit 99
  fi

  if ! git init ; then
    echo "Unable to create empty repo" >&2
    exit 99
  fi

  if ! git remote add origin "${gitrepourl}" ; then 
    echo "Unable to connect to ${gitrepourl}" >&2
    exit 99
  fi

  if ! git fetch --all ; then 
    echo "Unable to fetch from ${gitrepourl}" >&2
    exit 99
  fi

  if ! git checkout --track "origin/${main}" ; then
    echo "Unable to checkout to ${gitrepourl}/${main}" >&2
    exit 99
  fi
  
