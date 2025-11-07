{% from "ufw/vars.jinja" import vars with context %}

ufw:
  allow:
    ssh_all_servers:
      proto: tcp
      from:
        {{ vars["All_Servers"] }}
      to_port: 22
