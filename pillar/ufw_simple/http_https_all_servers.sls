{% from 'ufw_simple/vars.jinja' import vars with context %}

ufw_simple:
  enabled: True
  logging: 'off'
  allow:
    http_https_All_Servers_1:
      proto: 'tcp'
      from:
        {{ vars['All_Servers'] }}
      to_port: '80,443'
  delete:
    allow:
      http_https_All_Servers_1:
        proto: 'tcp'
        from:
          {{ vars['Delete_All_Servers'] }}
        to_port: '80,443'
