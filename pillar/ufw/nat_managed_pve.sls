ufw:
  enabled: True
  logging: 'off'
  nat:
    enabled: True
    masquerade:
      'masquerade from vm network':
        source: '10.0.20.0/24'
        out: 'br0'
