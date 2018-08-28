ufw_simple:
  enabled: True
  logging: 'off'
  allow:
    http:
      proto: 'tcp'
      to_port: '80'
    https:
      proto: 'tcp'
      to_port: '443'
