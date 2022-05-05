cmd_check_alert:
  network:
    files:
      /opt/sysadmws/cmd_check_alert/checks/exclude_network_iptables_open_from_any_safe.txt:
        proftpd: |
          --dport 5222
          --dport 5223
          --dport 7071
          --dport 8443
          --dport 80
          --dport 443
          --dport 25
          --dport 465
          --dport 587
          --dport 7780
          --dport 143
          --dport 993
          --dport 110
          --dport 995
