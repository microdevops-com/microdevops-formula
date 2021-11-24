{% from "ufw/vars.jinja" import vars with context %}
ufw:
  allow:
    http_https_from_any:
      proto: tcp
      to_port: 80,443
