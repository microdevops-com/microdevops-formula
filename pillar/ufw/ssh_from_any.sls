ufw:
  allow:
    ssh_from_any:
      proto: tcp
      to_port: 22

cmd_check_alert:
  network:
    files:
      /opt/sysadmws/cmd_check_alert/checks/exclude_network_iptables_open_from_any_safe.txt:
        ssh: |
          --dport 22
