#!/bin/bash

if [[ "_$1" == "_" || "_$2" == "_" || "_$3" == "_" ]]; then
	echo ERROR: needed args missing: use rsnapshot_backup_sync.sh TIMEOUT TARGET SSH/SALT SSH_HOST SSH_PORT SSH_JUMP
	echo ERROR: SSH_HOST, SSH_PORT, SSH_JUMP - optional
	exit 1
fi

GRAND_EXIT=0
SALT_TIMEOUT=$1
TARGET=$2
RSNAPSHOT_BACKUP_TYPE=$3
OUT_FILE="/srv/scripts/ci_sudo/$(basename $0)_${TARGET}.out"

if [[ "${RSNAPSHOT_BACKUP_TYPE}" == "SSH" ]]; then
	if [[ "_$6" == "_" ]]; then
		SSH_JUMP=""
	else
		SSH_JUMP="-J $6"
	fi
	if [[ "_$5" == "_" ]]; then
		SSH_PORT=22
	else
		SSH_PORT=$5
	fi
	if [[ "_$4" == "_" ]]; then
		SSH_HOST=${TARGET}
	else
		SSH_HOST=$4
	fi
fi

rm -f ${OUT_FILE}
exec > >(tee ${OUT_FILE})
exec 2>&1

set -x
set -o pipefail
if [[ "${RSNAPSHOT_BACKUP_TYPE}" == "SSH" ]]; then
	ssh -o BatchMode=yes -o StrictHostKeyChecking=no ${SSH_JUMP} -p ${SSH_PORT} ${SSH_HOST} \
		"bash -c 'exec 2>&1; /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.py --sync'" | ccze -A || GRAND_EXIT=1
elif [[ "${RSNAPSHOT_BACKUP_TYPE}" == "SALT" ]]; then
	salt --force-color -t ${SALT_TIMEOUT} ${TARGET} cmd.run \
		"bash -c 'exec 2>&1; /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.py --sync'" | ccze -A || GRAND_EXIT=1
else
	echo ERROR: unknown RSNAPSHOT_BACKUP_TYPE
	exit 1
fi
set +x

# Check out file for errors
grep -q "ERROR" ${OUT_FILE} && GRAND_EXIT=1
grep -q "CRITICAL" ${OUT_FILE} && GRAND_EXIT=1

# Check out file for red color with shades 
grep -q "\[0;31m" ${OUT_FILE} && GRAND_EXIT=1
grep -q "\[31m" ${OUT_FILE} && GRAND_EXIT=1
grep -q "\[0;1;31m" ${OUT_FILE} && GRAND_EXIT=1

exit $GRAND_EXIT
