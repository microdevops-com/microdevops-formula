#!/usr/bin/env bash

if [[ "_$1" == "_" || "_$2" == "_" ]]; then
	echo ERROR: needed args missing: use salt_cmd.sh TARGET CMD
	exit 1
fi

GRAND_EXIT=0
SALT_TARGET=$1
SALT_CMD_BASE64=$2
SALT_CMD=$(echo ${SALT_CMD_BASE64} | base64 -d)
OUT_FILE="$(mktemp -p /dev/shm/)"

exec > >(tee ${OUT_FILE})
exec 2>&1

if [[ -d /.salt-ssh-hooks ]]; then
	if [[ -r /.salt-ssh-hooks/${SALT_TARGET} ]]; then
		cat /.salt-ssh-hooks/${SALT_TARGET}
		source /.salt-ssh-hooks/${SALT_TARGET}
	fi
fi

set -x
# Passing through bash -c is important for state args, otherwise you might get error below on salt_cmds with pillar etc:
# TypeError encountered executing state.apply: apply_() takes from 0 to 1 positional arguments but 2 were given
bash -c "salt-ssh --wipe --force-color ${SALT_SSH_EXTRA_OPTS} ${SALT_TARGET} ${SALT_CMD}" || GRAND_EXIT=1
set +x

# Check out file for errors
grep -q "ERROR" ${OUT_FILE} && GRAND_EXIT=1

# Check out file for red color with shades 
grep -q "\[0;31m" ${OUT_FILE} && GRAND_EXIT=1
# Exclude prompts that have red color
cat ${OUT_FILE} | grep -v -e "byobu_prompt_status" | grep -q "\[31m" && GRAND_EXIT=1
grep -q "\[0;1;31m" ${OUT_FILE} && GRAND_EXIT=1

# Check for No matching sls found
grep -q "No matching sls found" ${OUT_FILE} && GRAND_EXIT=1

exit $GRAND_EXIT
