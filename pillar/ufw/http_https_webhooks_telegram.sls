ufw:
  allow:
    http_https_webhooks_telegram:
      proto: tcp
      from:
        webhooks_telegram_01: 149.154.160.0/20
        webhooks_telegram_02: 91.108.4.0/22
      to_port: 80,443
