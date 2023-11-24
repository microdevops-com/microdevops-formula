ufw:
  allow:
    http_https_from_any:
      proto: tcp
      to_port: 80,443

cmd_check_alert:
  network:
    files:
      /opt/sysadmws/cmd_check_alert/checks/exclude_network_iptables_open_from_any_safe.txt:
        http_https: |
          --dports 80,443
