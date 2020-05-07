#!/bin/bash
set -x

GRAND_EXIT=0

if [ "_$1" = "_" -o "_$2" = "_" -o "_$3" = "_" ]; then
	echo ERROR: needed args missing: use rsnapshot_backup_rotate.sh TIMEOUT TARGET SSH/SALT SSH_HOST SSH_PORT
	echo ERROR: SSH_HOST, SSH_PORT - optional
	exit 1
fi

SALT_TIMEOUT=$1
TARGET=$2
RSNAPSHOT_BACKUP_TYPE=$3

if [ "${RSNAPSHOT_BACKUP_TYPE}" = "SSH" ]; then
	if [ "_$5" = "_" ]; then
		SSH_PORT=22
	else
		SSH_PORT=$5
	fi
	if [ "_$4" = "_" ]; then
		SSH_HOST=${TARGET}
	else
		SSH_HOST=$4
	fi
fi
	
OUT_FILE="/srv/scripts/ci_sudo/$(basename $0)_${TARGET}.out"

rm -f ${OUT_FILE}
exec > >(tee ${OUT_FILE})
exec 2>&1

if [ "${RSNAPSHOT_BACKUP_TYPE}" = "SSH" ]; then
	# Monthly
	stdbuf -oL -eL echo ---
	( set -o pipefail && stdbuf -oL -eL ssh -o BatchMode=yes -o StrictHostKeyChecking=no -p ${SSH_PORT} ${SSH_HOST} "bash -c 'exec > >(tee /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.log); exec 2>&1; if [ $(date +%d) = 01 ]; then /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.sh monthly; fi'" | ccze -A | sed -e 's/33mNOTICE/32mNOTICE/' ) || GRAND_EXIT=1
	# Weekly
	stdbuf -oL -eL echo ---
	( set -o pipefail && stdbuf -oL -eL ssh -o BatchMode=yes -o StrictHostKeyChecking=no -p ${SSH_PORT} ${SSH_HOST} "bash -c 'exec > >(tee /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.log); exec 2>&1; if [ $(date +%u) = 1 ]; then /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.sh weekly; fi'" | ccze -A | sed -e 's/33mNOTICE/32mNOTICE/' ) || GRAND_EXIT=1
	# Daily
	stdbuf -oL -eL echo ---
	( set -o pipefail && stdbuf -oL -eL ssh -o BatchMode=yes -o StrictHostKeyChecking=no -p ${SSH_PORT} ${SSH_HOST} "bash -c 'exec > >(tee /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.log); exec 2>&1; /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.sh daily'" | ccze -A | sed -e 's/33mNOTICE/32mNOTICE/' ) || GRAND_EXIT=1
elif [ "${RSNAPSHOT_BACKUP_TYPE}" = "SALT" ]; then
	# Monthly
	stdbuf -oL -eL echo ---
	( set -o pipefail && stdbuf -oL -eL salt --force-color -t ${SALT_TIMEOUT} ${TARGET} cmd.run "bash -c 'exec > >(tee /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.log); exec 2>&1; if [ $(date +%d) = 01 ]; then /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.sh monthly; fi'" | ccze -A | sed -e 's/33mNOTICE/32mNOTICE/' ) || GRAND_EXIT=1
	# Weekly
	stdbuf -oL -eL echo ---
	( set -o pipefail && stdbuf -oL -eL salt --force-color -t ${SALT_TIMEOUT} ${TARGET} cmd.run "bash -c 'exec > >(tee /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.log); exec 2>&1; if [ $(date +%u) = 1 ]; then /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.sh weekly; fi'" | ccze -A | sed -e 's/33mNOTICE/32mNOTICE/' ) || GRAND_EXIT=1
	# Daily
	stdbuf -oL -eL echo ---
	( set -o pipefail && stdbuf -oL -eL salt --force-color -t ${SALT_TIMEOUT} ${TARGET} cmd.run "bash -c 'exec > >(tee /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.log); exec 2>&1; /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.sh daily'" | ccze -A | sed -e 's/33mNOTICE/32mNOTICE/' ) || GRAND_EXIT=1
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
