#!/bin/bash
GRAND_EXIT=0
SKIP_BACKUP_SERVER=0

if [ "_$1" != "_" ]; then
	if [ "$1" = "skip_backup_server" ]; then
		SKIP_BACKUP_SERVER=1
		MOD=""
		OUT_FILE="/srv/scripts/ci_sudo/$(basename $0).out"
	else
		MOD=" and $1"
		MOD_SHA=$(echo "$1" | sha1sum | awk '{print $1}')
		OUT_FILE="/srv/scripts/ci_sudo/$(basename $0)_${MOD_SHA}.out"
		if [ "_$2" != "_" ]; then
			if [ "$2" = "skip_backup_server" ]; then
				SKIP_BACKUP_SERVER=1
			fi
		fi
	fi
else
	MOD=""
	OUT_FILE="/srv/scripts/ci_sudo/$(basename $0).out"
fi

rm -f ${OUT_FILE}
exec > >(tee ${OUT_FILE})
exec 2>&1

stdbuf -oL -eL echo '---'
stdbuf -oL -eL echo 'CMD: salt --force-color -t 300 -C "I@rsnapshot_backup:*'${MOD}'" state.apply --state-output=filter --state-verbose=False exclude=True, sysadmws-utils.sysadmws-utils queue=True'
stdbuf -oL -eL salt --force-color -t 300 -C "I@rsnapshot_backup:*${MOD}" state.apply --state-output=filter --state-verbose=False exclude=True, sysadmws-utils.sysadmws-utils queue=True || GRAND_EXIT=1
stdbuf -oL -eL echo '---'
stdbuf -oL -eL echo 'CMD: salt --force-color -t 300 -C "I@rsnapshot_backup:*'${MOD}'" state.apply --state-output=filter --state-verbose=False exclude=True, rsnapshot_backup.put_check_files queue=True'
stdbuf -oL -eL salt --force-color -t 300 -C "I@rsnapshot_backup:*${MOD}" state.apply --state-output=filter --state-verbose=False exclude=True, rsnapshot_backup.put_check_files queue=True || GRAND_EXIT=1
stdbuf -oL -eL echo '---'
stdbuf -oL -eL echo 'CMD: salt --force-color -t 300 -C "I@rsnapshot_backup:*'${MOD}'" state.apply rsnapshot_backup.update_config queue=True'
stdbuf -oL -eL salt --force-color -t 300 -C "I@rsnapshot_backup:*${MOD}" state.apply rsnapshot_backup.update_config queue=True || GRAND_EXIT=1
stdbuf -oL -eL echo '---'
stdbuf -oL -eL echo 'CMD: salt --force-color -t 43200 -C "I@rsnapshot_backup:* and not G@os:Windows and not I@rsnapshot_backup:backup_server:True'${MOD}'" cmd.run "/opt/sysadmws/rsnapshot_backup/rsnapshot_backup_sync_monthly_weekly_daily_check_backup.sh"'
( stdbuf -oL -eL salt --force-color -t 43200 -C "I@rsnapshot_backup:* and not G@os:Windows and not I@rsnapshot_backup:backup_server:True${MOD}" cmd.run "/opt/sysadmws/rsnapshot_backup/rsnapshot_backup_sync_monthly_weekly_daily_check_backup.sh" || GRAND_EXIT=1 ) | ccze -A | sed -e 's/33mNOTICE/32mNOTICE/'

if [ ${SKIP_BACKUP_SERVER} -eq 0 ]; then
	stdbuf -oL -eL echo '---'
	stdbuf -oL -eL echo 'CMD: salt --force-color -t 43200 -C "I@rsnapshot_backup:backup_server:True'${MOD}'" cmd.run "/opt/sysadmws/rsnapshot_backup/rsnapshot_backup_sync_monthly_weekly_daily_check_backup.sh"'
	( stdbuf -oL -eL salt --force-color -t 43200 -C "I@rsnapshot_backup:backup_server:True${MOD}" cmd.run "/opt/sysadmws/rsnapshot_backup/rsnapshot_backup_sync_monthly_weekly_daily_check_backup.sh" || GRAND_EXIT=1 ) | ccze -A | sed -e 's/33mNOTICE/32mNOTICE/'
fi

grep -q "ERROR" ${OUT_FILE} && GRAND_EXIT=1

# 50 shades of red
grep -q "\[0;31m" ${OUT_FILE} && GRAND_EXIT=1
grep -q "\[31m" ${OUT_FILE} && GRAND_EXIT=1
grep -q "\[0;1;31m" ${OUT_FILE} && GRAND_EXIT=1

exit $GRAND_EXIT
