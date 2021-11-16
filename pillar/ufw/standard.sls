{% from "ufw/vars.jinja" import vars with context %}

ufw_simple:
  allow:
    standard_netdata:
      proto: tcp
      from:
        {{ vars["Office_And_VPN"] }}
      to_port: 19999
    standard_ssh_office_and_vpn:
      proto: tcp
      from:
        {{ vars["Office_And_VPN"] }}
      to_port: 22
    standard_ssh_backup_servers:
      proto: tcp
      from:
        {{ vars["Backup_Servers"] }}
      to_port: 22
