ufw_simple:
  enabled: True
  logging: 'off'
  allow:
    http_https_cloudflare:
      proto: 'tcp'
      from:
{% set auth_status = salt["cmd.shell"]("curl -sS -L https://www.cloudflare.com/ips-v4; curl -sS -L https://www.cloudflare.com/ips-v6") %}
{% for cf_net in auth_status.split("\n") %}
        cloudflare_{{ loop.index }}: {{ cf_net }}
{% endfor %}
      to_port: '80,443'
