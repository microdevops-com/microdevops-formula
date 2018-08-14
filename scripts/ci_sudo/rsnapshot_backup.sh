#!/bin/bash
GRAND_EXIT=0
rm -f /srv/scripts/ci_sudo/$(basename $0).out
exec > >(tee /srv/scripts/ci_sudo/$(basename $0).out)
exec 2>&1

if [ "_$1" != "_" ]; then
	MOD=" and $1"
else
	MOD=""
fi

stdbuf -oL -eL echo '---'
stdbuf -oL -eL echo 'CMD: salt --force-color -t 300 -C "I@rsnapshot_backup:*'${MOD}'" state.apply --state-output=filter --state-verbose=False exclude=True, rsnapshot_backup.put_check_files'
stdbuf -oL -eL salt --force-color -t 300 -C "I@rsnapshot_backup:*${MOD}" state.apply --state-output=filter --state-verbose=False exclude=True, rsnapshot_backup.put_check_files || GRAND_EXIT=1
stdbuf -oL -eL echo '---'
stdbuf -oL -eL echo 'CMD: salt --force-color -t 300 -C "I@rsnapshot_backup:*'${MOD}'" state.apply rsnapshot_backup.update_config'
stdbuf -oL -eL salt --force-color -t 300 -C "I@rsnapshot_backup:*${MOD}" state.apply rsnapshot_backup.update_config || GRAND_EXIT=1
stdbuf -oL -eL echo '---'
stdbuf -oL -eL echo 'CMD: salt --force-color -t 43200 -C "I@rsnapshot_backup:* and not I@rsnapshot_backup:backup_server:True'${MOD}'" cmd.run "/opt/sysadmws/rsnapshot_backup/rsnapshot_backup_sync_monthly_weekly_daily_check_backup.sh"'
( stdbuf -oL -eL salt --force-color -t 43200 -C "I@rsnapshot_backup:* and not I@rsnapshot_backup:backup_server:True${MOD}" cmd.run "/opt/sysadmws/rsnapshot_backup/rsnapshot_backup_sync_monthly_weekly_daily_check_backup.sh" || GRAND_EXIT=1 ) | ccze -A | sed -e 's/33mNOTICE/32mNOTICE/'
stdbuf -oL -eL echo '---'
stdbuf -oL -eL echo 'CMD: salt --force-color -t 43200 -C "I@rsnapshot_backup:backup_server:True'${MOD}'" cmd.run "/opt/sysadmws/rsnapshot_backup/rsnapshot_backup_sync_monthly_weekly_daily_check_backup.sh"'
( stdbuf -oL -eL salt --force-color -t 43200 -C "I@rsnapshot_backup:backup_server:True${MOD}" cmd.run "/opt/sysadmws/rsnapshot_backup/rsnapshot_backup_sync_monthly_weekly_daily_check_backup.sh" || GRAND_EXIT=1 ) | ccze -A | sed -e 's/33mNOTICE/32mNOTICE/'

# Shades of red
grep -q "\[0;31m" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1
grep -q "\[31m" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1

exit $GRAND_EXIT
