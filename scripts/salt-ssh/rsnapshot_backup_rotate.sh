#!/usr/bin/env bash

if [[ "_$1" == "_" || "_$2" == "_" ]]; then
	echo ERROR: needed args missing: use rsnapshot_backup_rotate.sh TARGET SSH/SALT SSH_HOST SSH_PORT SSH_JUMP
	echo ERROR: SSH_HOST, SSH_PORT, SSH_JUMP - optional
	exit 1
fi

GRAND_EXIT=0
TARGET=$1
RSNAPSHOT_BACKUP_TYPE=$2
OUT_FILE="$(mktemp -p /dev/shm/)"

if [[ "${RSNAPSHOT_BACKUP_TYPE}" == "SSH" ]]; then
	if [[ "_$5" == "_" ]]; then
		SSH_JUMP=""
	else
		SSH_JUMP="-J $5"
	fi
	if [[ "_$4" == "_" ]]; then
		SSH_PORT=22
	else
		SSH_PORT=$4
	fi
	if [[ "_$3" == "_" ]]; then
		SSH_HOST=${TARGET}
	else
		SSH_HOST=$3
	fi
fi

exec > >(tee ${OUT_FILE})
exec 2>&1

if [[ -d /.salt-ssh-hooks ]]; then
	if [[ -r /.salt-ssh-hooks/${TARGET} ]]; then
		cat /.salt-ssh-hooks/${TARGET}
		source /.salt-ssh-hooks/${TARGET}
	fi
fi

set -x
set -o pipefail
if [[ "${RSNAPSHOT_BACKUP_TYPE}" == "SSH" ]]; then
	if salt-ssh --wipe ${SALT_SSH_EXTRA_OPTS} ${TARGET} pillar.get rsnapshot_backup:python | grep -q -e True; then
		# Monthly
		ssh -o BatchMode=yes -o StrictHostKeyChecking=no ${SSH_JUMP} -p ${SSH_PORT} ${SSH_HOST} \
			"bash -c 'exec 2>&1; if [[ $(date +%d) == 01 ]]; then /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.py --rotate-monthly; fi'" | ccze -A || GRAND_EXIT=1
		# Weekly
		ssh -o BatchMode=yes -o StrictHostKeyChecking=no ${SSH_JUMP} -p ${SSH_PORT} ${SSH_HOST} \
			"bash -c 'exec 2>&1; if [[ $(date +%u) == 1 ]]; then /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.py --rotate-weekly; fi'" | ccze -A || GRAND_EXIT=1
		# Daily
		ssh -o BatchMode=yes -o StrictHostKeyChecking=no ${SSH_JUMP} -p ${SSH_PORT} ${SSH_HOST} \
			"bash -c 'exec 2>&1; /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.py --rotate-daily'" | ccze -A || GRAND_EXIT=1
	else
		# Monthly
		ssh -o BatchMode=yes -o StrictHostKeyChecking=no ${SSH_JUMP} -p ${SSH_PORT} ${SSH_HOST} \
			"bash -c 'exec 2>&1; if [[ $(date +%d) == 01 ]]; then /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.sh monthly; fi'" | ccze -A || GRAND_EXIT=1
		# Weekly
		ssh -o BatchMode=yes -o StrictHostKeyChecking=no ${SSH_JUMP} -p ${SSH_PORT} ${SSH_HOST} \
			"bash -c 'exec 2>&1; if [[ $(date +%u) == 1 ]]; then /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.sh weekly; fi'" | ccze -A || GRAND_EXIT=1
		# Daily
		ssh -o BatchMode=yes -o StrictHostKeyChecking=no ${SSH_JUMP} -p ${SSH_PORT} ${SSH_HOST} \
			"bash -c 'exec 2>&1; /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.sh daily'" | ccze -A || GRAND_EXIT=1
	fi
elif [[ "${RSNAPSHOT_BACKUP_TYPE}" == "SALT" ]]; then
	if salt-ssh --wipe ${SALT_SSH_EXTRA_OPTS} ${TARGET} pillar.get rsnapshot_backup:python | grep -q -e True; then
		# Monthly
		salt-ssh --wipe --force-color ${SALT_SSH_EXTRA_OPTS} ${TARGET} cmd.run \
			"bash -c 'exec 2>&1; if [[ $(date +%d) == 01 ]]; then /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.py --rotate-monthly; fi'" | ccze -A || GRAND_EXIT=1
		# Weekly
		salt-ssh --wipe --force-color ${SALT_SSH_EXTRA_OPTS} ${TARGET} cmd.run \
			"bash -c 'exec 2>&1; if [[ $(date +%u) == 1 ]]; then /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.py --rotate-weekly; fi'" | ccze -A || GRAND_EXIT=1
		# Daily
		salt-ssh --wipe --force-color ${SALT_SSH_EXTRA_OPTS} ${TARGET} cmd.run \
			"bash -c 'exec 2>&1; /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.py --rotate-daily'" | ccze -A || GRAND_EXIT=1
	else
		# Monthly
		salt-ssh --wipe --force-color ${SALT_SSH_EXTRA_OPTS} ${TARGET} cmd.run \
			"bash -c 'exec 2>&1; if [[ $(date +%d) == 01 ]]; then /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.sh monthly; fi'" | ccze -A || GRAND_EXIT=1
		# Weekly
		salt-ssh --wipe --force-color ${SALT_SSH_EXTRA_OPTS} ${TARGET} cmd.run \
			"bash -c 'exec 2>&1; if [[ $(date +%u) == 1 ]]; then /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.sh weekly; fi'" | ccze -A || GRAND_EXIT=1
		# Daily
		salt-ssh --wipe --force-color ${SALT_SSH_EXTRA_OPTS} ${TARGET} cmd.run \
			"bash -c 'exec 2>&1; /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.sh daily'" | ccze -A || GRAND_EXIT=1
	fi
else
	echo ERROR: unknown RSNAPSHOT_BACKUP_TYPE
	exit 1
fi
set +x

# Check out file for errors
grep -q "ERROR" ${OUT_FILE} && GRAND_EXIT=1

# Check out file for red color with shades 
grep -q "\[0;31m" ${OUT_FILE} && GRAND_EXIT=1
grep -q "\[31m" ${OUT_FILE} && GRAND_EXIT=1
grep -q "\[0;1;31m" ${OUT_FILE} && GRAND_EXIT=1

exit $GRAND_EXIT
