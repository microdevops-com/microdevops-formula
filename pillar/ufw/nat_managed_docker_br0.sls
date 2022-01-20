ufw:
  enabled: True
  logging: 'off'
  nat:
    enabled: True
    masquerade:
      'masquerade from docker networks to br0':
        source: '172.16.0.0/12'
        out: 'br0'
