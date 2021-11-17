{% from "ufw/vars.jinja" import vars with context %}

ufw:
  allow:
    ssh_from_salt_servers:
      proto: tcp
      from:
        {{ vars["Salt_Servers"] }}
      to_port: 22
