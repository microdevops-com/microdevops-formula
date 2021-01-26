cmd_check_alert:
  checks:
    mysqld:
      cmd: systemctl is-active mysql.service && ps ax | grep '/usr/sbin/mysql[d]'
      service: service
      resource: __hostname__:mysqld
