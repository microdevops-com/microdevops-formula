#!/bin/bash
GRAND_EXIT=0

if [ "_$1" = "_" -o "_$2" = "_" -o "_$3" = "_" ]; then
	echo ERROR: needed args missing: use salt_cmd TIMEOUT TARGET CMD
	exit 1
fi

SALT_TIMEOUT=$1
SALT_TARGET=$2
SALT_CMD=$3
	
CMD_SHA=$(echo "$2,$3" | sha1sum | awk '{print $1}')
OUT_FILE="/srv/scripts/ci_sudo/$(basename $0)_${CMD_SHA}.out"

rm -f ${OUT_FILE}
exec > >(tee ${OUT_FILE})
exec 2>&1

stdbuf -oL -eL echo ---
stdbuf -oL -eL echo CMD: salt --force-color -t ${SALT_TIMEOUT} ${SALT_TARGET} ${SALT_CMD} queue=True
stdbuf -oL -eL           salt --force-color -t ${SALT_TIMEOUT} ${SALT_TARGET} ${SALT_CMD} queue=True || GRAND_EXIT=1

# Check out file for errors
grep -q "ERROR" ${OUT_FILE} && GRAND_EXIT=1

# Check out file for red color with shades 
grep -q "\[0;31m" ${OUT_FILE} && GRAND_EXIT=1
grep -q "\[31m" ${OUT_FILE} && GRAND_EXIT=1
grep -q "\[0;1;31m" ${OUT_FILE} && GRAND_EXIT=1

exit $GRAND_EXIT
