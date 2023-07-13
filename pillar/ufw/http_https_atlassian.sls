ufw:
  allow:
    http_https_atlassian:
      proto: tcp
      from:
{% set atl_nets = salt["cmd.shell"]("curl -sS -L https://ip-ranges.atlassian.com | jq -r .items[].cidr") %}
{% for atl_net in atl_nets.split("\n") %}
        atlassian_{{ loop.index }}: {{ atl_net }}
{% endfor %}
      to_port: 80,443
