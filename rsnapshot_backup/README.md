These formula states configure [sysadmws-utils](https://github.com/sysadmws/sysadmws-utils) rsnapshot_backup.

The rsnapshot_backup is a wrapper that generates rsnapshot.conf and runs rsnapshot.

Typical usage:
- install sysadmws-utils-v1 on minion
- define and refresh rsnapshot_backup pillar
- `salt minion state.apply rsnapshot_backup.put_check_files` to put special file for check purposes
- `salt minion state.apply rsnapshot_backup.update_config` to update json config from pillar
- `salt minion cmd.run /opt/sysadmws/rsnapshot_backup/rsnapshot_backup_sync_monthly_weekly_daily_check_backup.sh` to do sync, rotations and checks
- `salt minion state.apply rsnapshot_backup.check_coverage` to check backup coverage
