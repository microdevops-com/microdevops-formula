{% from "ufw/vars.jinja" import vars with context %}

ufw:
  allow:
    k8s_master_office_and_vpn:
      proto: tcp
      from:
        {{ vars["Office_And_VPN"] }}
      to_port: 6443
