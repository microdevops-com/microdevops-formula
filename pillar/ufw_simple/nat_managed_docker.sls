ufw_simple:
  enabled: True
  logging: 'off'
  nat:
    enabled: True
    masquerade:
      'masquerade from docker networks':
        source: '172.0.0.0/8'
        out: 'br0'
