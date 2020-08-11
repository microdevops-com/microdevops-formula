cmd_check_alert:
  checks:
    salt-master:
      cmd: systemctl is-active salt-master.service && ps ax | grep '/usr/bin/salt-maste[r]'
      service: service
      resource: __hostname__:salt-master
