{% from 'ufw_simple/vars.jinja' import vars with context %}

ufw_simple:
  enabled: True
  logging: 'off'
  allow:
    ssh_salt_servers:
      proto: 'tcp'
      from:
        {{ vars['Salt_Servers'] }}
      to_port: '22'
  delete:
    allow:
      ssh_salt_servers:
        proto: 'tcp'
        from:
          {{ vars['Delete_Salt_Servers'] }}
        to_port: '22'
