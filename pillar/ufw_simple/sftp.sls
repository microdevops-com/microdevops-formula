ufw_simple:
  enabled: True
  logging: 'off'
  allow:
    http:
      proto: 'tcp'
      to_port: '2226'

cmd_check_alert:
  network:
    files:
      /opt/sysadmws/cmd_check_alert/checks/exclude_network_iptables_open_from_any_safe.txt:
        sftp: |
          --dport 2226
