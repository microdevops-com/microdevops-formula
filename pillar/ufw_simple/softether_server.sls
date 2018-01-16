ufw_simple:
  enabled: True
  logging: 'off'
  allow:
    vpn_IPSec_IKE:
      proto: 'udp'
      to_port: '500'
    vpn_IPSec_NAT:
      proto: 'udp'
      to_port: '4500'
    vpn_OpenVpn:
      proto: 'udp'
      to_port: '1194'
    vpn_SoftEther:
      proto: 'tcp'
      to_port: '5555'
