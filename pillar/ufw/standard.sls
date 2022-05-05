{% from "ufw/vars.jinja" import vars with context %}

ufw:
  allow:
    standard_allow_ports:
      proto: tcp
      from:
        {{ vars["Office_And_VPN"] }}
      to_port: 22,80,443,19999
    standard_ssh_backup_servers:
      proto: tcp
      from:
        {{ vars["Backup_Servers"] }}
      to_port: 22
