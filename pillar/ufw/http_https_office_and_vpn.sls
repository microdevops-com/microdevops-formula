{% from "ufw/vars.jinja" import vars with context %}

ufw:
  allow:
    http_https_office_and_vpn:
      proto: tcp
      from:
        {{ vars["Office_And_VPN"] }}
      to_port: 80,443
