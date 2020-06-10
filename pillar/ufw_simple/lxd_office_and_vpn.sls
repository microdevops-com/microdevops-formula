{% from 'ufw_simple/vars.jinja' import vars with context %}

ufw_simple:
  enabled: True
  logging: 'off'
  allow:
    lxd_office_and_vpn:
      proto: 'tcp'
      from:
        {{ vars['Office_And_VPN'] }}
      to_port: '8443'
  delete:
    allow:
      lxd_office_and_vpn:
        proto: 'tcp'
        from:
          {{ vars['Delete_Office_And_VPN'] }}
        to_port: '8443'
