{% load_yaml as cmd %}
curl -sSL https://ip-ranges.atlassian.com/ | jq  -r '.items[] | select( (.direction == ["egress"]) and (.product == ["bitbucket"]) ) | .cidr'
{% endload %}
{% set bb_nets = salt["cmd.run"](shell="/bin/bash", cmd=cmd, python_shell=True) %}
ufw:
  allow:
    bitbucket_pipelines_ip:
      proto: tcp
      from:
{% for bb_net in bb_nets.split("\n") %}
        bb_{{ loop.index }}: {{ bb_net }}
{% endfor %}
      to_port: 22
