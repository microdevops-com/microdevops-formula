ufw:
  allow:
    http_https_cloudflare:
      proto: tcp
      from:
{% set cf_nets = salt["cmd.shell"]("curl -sS -L https://www.cloudflare.com/ips-v4;  echo '';curl -sS -L https://www.cloudflare.com/ips-v6") %}
{% for cf_net in cf_nets.split("\n") %}
        cloudflare_{{ loop.index }}: {{ cf_net }}
{% endfor %}
      to_port: 80,443
