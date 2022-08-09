{% from "ufw/vars.jinja" import vars with context %}

ufw:
  allow:
    k8s_ingress_office_and_vpn:
      proto: tcp
      from:
        {{ vars["Office_And_VPN"] }}
      to_port: 6443
