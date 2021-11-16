{% from "ufw/vars.jinja" import vars with context %}

ufw_simple:
  allow:
    salt_master:
      proto: tcp
      from:
        {{ vars["All_Servers"] }}
      to_port: 4505,4506
