{% from 'ufw_simple/vars.jinja' import vars with context %}

ufw_simple:
  enabled: True
  logging: 'off'
  allow:
    http_https_Office_And_VPN_1:
      proto: 'tcp'
      from:
        {{ vars['Office_And_VPN'] }}
      to_port: '80,443'
  delete:
    allow:
      http_https_Office_And_VPN_1:
        proto: 'tcp'
        from:
          {{ vars['Delete_Office_And_VPN'] }}
        to_port: '80,443'
