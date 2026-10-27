#!/bin/sh
set -e

mydir=$(cd $(dirname $0) && echo $PWD)

# The following is a bit hokey... might not always work
#
gitdir="${mydir}/../git"
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

export GIT_TEMPLATE_DIR="${mydir}/../git/templates/blt"
export GIT_EXEC_PATH="${mydir}/../git/libexec/git-core"
gitrepourl="git@github.com:IgorTodorovskiIBM/EBCDICProject.git"
git clone $gitrepourl

cat > expected.txt <<ZZ
b binary      T=off a.png
t IBM-037     T=on  my_037.txt
t IBM-1047    T=on  ebcdic.txt
t ISO8859-1   T=on  CONFLICT.txt
t ISO8859-1   T=on  README.md
t ISO8859-1   T=on  ascii.txt
t ISO8859-1   T=on  cacert.pem
t ISO8859-1   T=on  cacert.pem2
t ISO8859-1   T=on  d.mac
t ISO8859-1   T=on  utf8.sh
t ISO8859-1   T=on  utf8.txt
ZZ
cd EBCDICProject
chtag -p * 2>/dev/null | sort > ../actual.txt
iconv -f IBM-037 -t IBM-1047 my_037.txt > my_1047.txt
chtag -tc 1047 my_1047.txt

# Just verify the files exist and basic content
[ -f README.md ] || { echo "FAIL: README.md missing"; exit 1; }
[ -f ascii.txt ] || { echo "FAIL: ascii.txt missing"; exit 1; }
[ -f my_1047.txt ] || { echo "FAIL: my_1047.txt missing"; exit 1; }

# Verify first line of each file contains "Hello World"
head -1 README.md | grep -q "Hello World" || { echo "FAIL: README.md content wrong"; exit 1; }
head -1 ascii.txt | grep -q "Hello World" || { echo "FAIL: ascii.txt content wrong"; exit 1; }
head -1 my_1047.txt | grep -q "Hello World" || { echo "FAIL: my_1047.txt content wrong"; exit 1; }

cd ..
# Compare tag output
diff actual.txt expected.txt || { echo "FAIL: file tags don't match expected"; exit 1; }

echo "Test passed"
exit 0


