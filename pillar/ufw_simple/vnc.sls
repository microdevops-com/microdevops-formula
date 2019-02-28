{% from 'ufw_simple/vars.jinja' import vars with context %}

ufw_simple:
  enabled: True
  logging: 'off'
  allow:
    vnc:
      proto: 'tcp'
      from:
        {{ vars['Office_And_VPN'] }}
      to_port: '5900'
  delete:
    allow:
      vnc:
        proto: 'tcp'
        from:
          {{ vars['Delete_Office_And_VPN'] }}
        to_port: '5900'
