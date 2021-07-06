ufw_simple:
  enabled: True
  logging: 'off'
  allow:
    vpn_over_HTTPS:
      proto: 'tcp'
      to_port: '443'
    vpn_IPSec_IKE:
      proto: 'udp'
      to_port: '500'
    vpn_IPSec_NAT:
      proto: 'udp'
      to_port: '4500'
    vpn_OpenVpn_udp:
      proto: 'udp'
      to_port: '1194'
    vpn_OpenVpn_tcp:
      proto: 'tcp'
      to_port: '1194'
    vpn_SoftEther:
      proto: 'tcp'
      to_port: '5555'
cmd_check_alert:
  network:
    files:
      /opt/sysadmws/cmd_check_alert/checks/exclude_network_iptables_open_from_any_safe.txt:
        softether_vpnserver: |
          --dport 443
          --dport 500
          --dport 4500
          --dport 1194
          --dport 5555
