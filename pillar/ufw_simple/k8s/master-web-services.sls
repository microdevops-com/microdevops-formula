{% from '/srv/pillar/ufw_simple/vars.jinja' import vars with context %}

ufw_simple:
  allow:
    k8s-master-web-services:
      proto: 'tcp'
      from:
        {{ vars['Office_And_VPN'] }}
      to_port: '6443'
