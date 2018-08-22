This formula module configures [sysadmws-utils](https://github.com/sysadmws/sysadmws-utils) rsnapshot_backup module.

The rsnapshot_backup is a wrapper that generates rsnapshot.conf and runs rsnapshot.

Typical usage:
- install sysadmws-utils-v1 on minion
- define and refresh rsnapshot_backup pillar
- salt minion state.apply rsnapshot_backup.put_check_files # put special file for check purposes
- salt minion state.apply rsnapshot_backup.update_config # update json config from pillar
- salt minion cmd.run /opt/sysadmws/rsnapshot_backup/rsnapshot_backup_sync_monthly_weekly_daily_check_backup.sh # do sync, rotations and checks

Real script for CI usage is at scripts/ci_sudo/rsnapshot_backup.sh .
