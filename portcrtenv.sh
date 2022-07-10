#!/bin/sh
install_dir="$1"

cat <<zz >"${install_dir}/.env"
if ! [ -f ./.env ]; then
	echo "Need to source from the .env directory" >&2
	return 0
fi
mydir="\${PWD}"
export PATH="\${mydir}/bin:\$PATH"
zz
exit 0
