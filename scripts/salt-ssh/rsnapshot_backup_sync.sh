#!/usr/bin/env bash
GRAND_EXIT=0

if [[ "_$1" = "_" || "_$2" = "_" ]]; then
	echo ERROR: needed args missing: use rsnapshot_backup_sync.sh TARGET SSH/SALT SSH_HOST SSH_PORT SSH_JUMP
	echo ERROR: SSH_HOST, SSH_PORT, SSH_JUMP - optional
	exit 1
fi

TARGET=$1
RSNAPSHOT_BACKUP_TYPE=$2

if [ "${RSNAPSHOT_BACKUP_TYPE}" = "SSH" ]; then
	if [ "_$5" = "_" ]; then
		SSH_JUMP=""
	else
		SSH_JUMP="-J $5"
	fi
	if [ "_$4" = "_" ]; then
		SSH_PORT=22
	else
		SSH_PORT=$4
	fi
	if [ "_$3" = "_" ]; then
		SSH_HOST=${TARGET}
	else
		SSH_HOST=$3
	fi
fi
	
OUT_FILE="$(mktemp -p /dev/shm/)"

exec > >(tee ${OUT_FILE})
exec 2>&1

if [[ -d /.salt-ssh-hooks ]]; then
	if [[ -r /.salt-ssh-hooks/${TARGET} ]]; then
		cat /.salt-ssh-hooks/${TARGET}
		source /.salt-ssh-hooks/${TARGET}
	fi
fi

if [ "${RSNAPSHOT_BACKUP_TYPE}" = "SSH" ]; then
	( set -x ; set -o pipefail && stdbuf -oL -eL ssh -o BatchMode=yes -o StrictHostKeyChecking=no ${SSH_JUMP} -p ${SSH_PORT} ${SSH_HOST} "bash -c 'exec > >(tee /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.log); exec 2>&1; /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.sh sync'" | ccze -A ) || GRAND_EXIT=1
elif [ "${RSNAPSHOT_BACKUP_TYPE}" = "SALT" ]; then
	( set -x ; set -o pipefail && stdbuf -oL -eL salt-ssh --wipe --force-color ${SALT_SSH_EXTRA_OPTS} ${TARGET} cmd.run "bash -c 'exec > >(tee /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.log); exec 2>&1; /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.sh sync'" | ccze -A ) || GRAND_EXIT=1
else
	echo ERROR: unknown RSNAPSHOT_BACKUP_TYPE
	exit 1
fi

# Check out file for errors
grep -q "ERROR" ${OUT_FILE} && GRAND_EXIT=1

# Check out file for red color with shades 
grep -q "\[0;31m" ${OUT_FILE} && GRAND_EXIT=1
grep -q "\[31m" ${OUT_FILE} && GRAND_EXIT=1
grep -q "\[0;1;31m" ${OUT_FILE} && GRAND_EXIT=1

exit $GRAND_EXIT
