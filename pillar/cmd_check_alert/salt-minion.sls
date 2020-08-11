cmd_check_alert:
  checks:
    salt-minion:
      cmd: systemctl is-active salt-minion.service && ps ax | grep '/usr/bin/salt-minio[n]'
      service: service
      resource: __hostname__:salt-minion
