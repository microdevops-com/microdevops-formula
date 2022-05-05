ufw_simple:
  enabled: True
  logging: 'off'
  allow:
    http_https_googlebot:
      proto: 'tcp'
      from:
{% set googlebot_nets = salt["cmd.shell"]("curl -Ss https://developers.google.com/search/apis/ipranges/googlebot.json |jq -r '.prefixes | .[] |.ipv4Prefix//empty,.ipv6Prefix//empty'") %}
{% for googlebot_net in googlebot_nets.split("\n") %}
        googlebot_{{ loop.index }}: {{ googlebot_net }}
{% endfor %}
      to_port: '80,443'
