ufw_simple:
  enabled: True
  logging: 'off'
  allow:
    http_https_cloudflare:
      proto: 'tcp'
      from:
        cloudflare_01: '103.21.244.0/22'
        cloudflare_02: '103.22.200.0/22'
        cloudflare_03: '103.31.4.0/22'
        cloudflare_04: '104.16.0.0/12'
        cloudflare_05: '108.162.192.0/18'
        cloudflare_06: '131.0.72.0/22'
        cloudflare_07: '141.101.64.0/18'
        cloudflare_08: '162.158.0.0/15'
        cloudflare_09: '172.64.0.0/13'
        cloudflare_10: '173.245.48.0/20'
        cloudflare_11: '188.114.96.0/20'
        cloudflare_12: '190.93.240.0/20'
        cloudflare_13: '197.234.240.0/22'
        cloudflare_14: '198.41.128.0/17'
        cloudflare_15: '2400:cb00::/32'
        cloudflare_16: '2405:8100::/32'
        cloudflare_17: '2405:b500::/32'
        cloudflare_18: '2606:4700::/32'
        cloudflare_19: '2803:f800::/32'
        cloudflare_20: '2c0f:f248::/32'
        cloudflare_21: '2a06:98c0::/29'
      to_port: '80,443'
