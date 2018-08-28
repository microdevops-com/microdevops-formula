ufw_simple:
  enabled: True
  logging: 'off'
  allow:
    unifi-video:
      proto: 'tcp'
      to_port: '6666,7080,7443,7445,7446,7447,443,80,8446'
  nat:
    redirect:
      'catch https unifi live video port 7446 and redirect -> nginx le https 8446 -> nginx proxy to unifi live video on http 7445':
        dport: '7446'
        to_ports: '8446'
        proto: 'tcp'
        in: 'eth0'
