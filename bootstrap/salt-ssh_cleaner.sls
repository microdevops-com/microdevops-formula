cron_tmp_remove:
  cron.present:
    - name: /usr/bin/find /var/tmp -name '.*_*_salt' -mtime +1 -exec rm -fr {} \;
    - identifier: Clean unnecessary Salt files
    - user: root
    - minute: 26
    - hour: 3
