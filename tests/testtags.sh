#!/bin/sh

mydir=$(cd $(dirname $0) && echo $PWD)


# The following is a bit hokey... might not always work
#
gitdir="${mydir}/../git-2.38.1"
echo $gitdir
if ! [ -d "${gitdir}" ] ; then
  echo "Unable to find git dev driver" >&2
  exit 99
fi
absgitdir=$(cd ${gitdir} && echo $PWD)

export PATH=/bin:/usr/bin:${absgitdir}

tmpdir="/tmp/git-$$"
mkdir "${tmpdir}" || exit 99             
cd "${tmpdir}" || exit 99
touch ".gitconfig" || exit 99
echo $PWD

export GIT_TEMPLATE_DIR="${mydir}/../git-2.38.1/templates/blt"
export GIT_EXEC_PATH="${mydir}/../git-2.38.1/libexec/git-core"
gitrepourl="git@github.com:IgorTodorovskiIBM/EBCDICProject.git"
git clone $gitrepourl

cat > expected.txt <<ZZ
t IBM-1047    T=on  README.md
b binary      T=off a.png
t ISO8859-1   T=on  ascii.txt
ZZ
cd EBCDICProject
chtag -p * > ../actual.txt
cat README.md ascii.txt > ../actual2.txt
cd ..
diff actual.txt expected.txt

cat > expected2.txt <<ZZ
Hello World
Hello World
ZZ
diff actual2.txt expected2.txt

