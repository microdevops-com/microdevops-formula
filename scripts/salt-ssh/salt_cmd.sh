#!/usr/bin/env bash
GRAND_EXIT=0

if [[ "_$1" = "_" || "_$2" = "_" ]]; then
	echo ERROR: needed args missing: use salt_cmd.sh TARGET CMD
	exit 1
fi

SALT_TARGET=$1
SALT_CMD_BASE64=$2
SALT_CMD=$(echo ${SALT_CMD_BASE64} | base64 -d)
	
OUT_FILE="$(mktemp -p /dev/shm/)"

exec > >(tee ${OUT_FILE})
exec 2>&1

( set -x ; stdbuf -oL -eL  bash -c "salt-ssh --force-color ${SALT_TARGET} ${SALT_CMD}" ) || GRAND_EXIT=1

# Check out file for errors
grep -q "ERROR" ${OUT_FILE} && GRAND_EXIT=1

# Check out file for red color with shades 
grep -q "\[0;31m" ${OUT_FILE} && GRAND_EXIT=1
# Exclude prompts that have red color
cat ${OUT_FILE} | grep -v -e "byobu_prompt_status" | grep -q "\[31m" && GRAND_EXIT=1
grep -q "\[0;1;31m" ${OUT_FILE} && GRAND_EXIT=1

exit $GRAND_EXIT
