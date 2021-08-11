ufw_simple:
  enabled: True
  logging: 'off'
  nat:
    enabled: True
    masquerade:
      'masquerade from docker networks to enp5s0':
        source: '172.16.0.0/12'
        out: 'enp5s0'
