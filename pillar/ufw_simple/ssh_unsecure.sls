ufw_simple:
  enabled: True
  logging: 'off'
  allow:
    ssh_x:
      proto: 'tcp'
      to_port: '22'
