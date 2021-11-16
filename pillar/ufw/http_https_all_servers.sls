{% from "ufw/vars.jinja" import vars with context %}

ufw_simple:
  allow:
    http_https_all_servers:
      proto: tcp
      from:
        {{ vars["All_Servers"] }}
      to_port: 80,443
