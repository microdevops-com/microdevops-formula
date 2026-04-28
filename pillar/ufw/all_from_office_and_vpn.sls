{% from "ufw/vars.jinja" import vars with context %}

ufw:
  allow:
    all_from_office_and_vpn:
      proto: tcp
      from:
        {{ vars["Office_And_VPN"] }}
