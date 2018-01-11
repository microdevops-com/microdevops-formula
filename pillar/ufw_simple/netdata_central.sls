{% from '/srv/pillar/ufw_simple/vars.jinja' import vars with context %}

ufw_simple:
  enabled: True
  logging: 'off'
  allow:
    netdata_2:
      proto: 'tcp'
      from:
        {{ vars['All_Servers'] }}
      to_port: '19999'
    web_1:
      proto: 'tcp'
      from:
        {{ vars['Office_And_VPN'] }}
      to_port: '80,443'
