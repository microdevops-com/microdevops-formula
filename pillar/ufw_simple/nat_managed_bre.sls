ufw_simple:
  enabled: True
  logging: 'off'
  nat:
    enabled: True
    masquerade:
      'masquerade from vm-host network':
        source: '10.0.10.0/24'
        out: 'bre'
