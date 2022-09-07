{% from "ufw/vars.jinja" import vars with context %}
ufw:
  allow:
    postgresql_from_docker:
      proto: tcp
      from:
        own_docker: 172.16.0.0/12
      to_port: 5432
