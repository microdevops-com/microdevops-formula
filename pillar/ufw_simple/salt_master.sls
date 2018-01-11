{% from '/srv/pillar/ufw_simple/vars.jinja' import vars with context %}

ufw_simple:
  enabled: True
  logging: 'off'
  allow:
    salt:
      proto: 'tcp'
      from:
        {{ vars['All_Servers'] }}
      to_port: '4505,4506'
