{% from '/srv/pillar/ufw_simple/vars.jinja' import vars with context %}

ufw_simple:
  enabled: True
  logging: 'off'
  allow:
    netdata:
      proto: 'tcp'
      from:
        {{ vars['Office_And_VPN'] }}
      to_port: '19999'
    ssh_1:
      proto: 'tcp'
      from:
        {{ vars['Office_And_VPN'] }}
      to_port: '22'
    ssh_2:
      proto: 'tcp'
      from:
        {{ vars['Backup_Servers'] }}
      to_port: '22'
