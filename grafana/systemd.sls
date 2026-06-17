{% if pillar["grafana"] is defined and pillar["grafana"] is not none and pillar["grafana"]["systemd"] is defined %}

  {%- set grafana = pillar["grafana"]["systemd"] %}

grafana_systemd_repo:
  pkgrepo.managed:
    - humanname: Grafana Repository
    - name: deb https://apt.grafana.com stable main
    - file: /etc/apt/sources.list.d/grafana.list
    - key_url: https://apt.grafana.com/gpg.key
    - clean_file: True

grafana_systemd_deps:
  pkg.installed:
    - pkgs:
      - apt-transport-https
      - software-properties-common

grafana_systemd_pkg:
  {%- if grafana["version"] is defined and grafana["version"] != "latest" %}
  pkg.installed:
    - refresh: True
    - pkgs:
      - grafana: {{ grafana["version"] }}
  {%- else %}
  pkg.latest:
    - refresh: True
    - pkgs:
      - grafana
  {%- endif %}
    - require:
      - pkgrepo: grafana_systemd_repo

# Set port and admin password via environment in the package-provided
# defaults file, keeping the rest of its content (GRAFANA_USER, DATA_DIR, etc.) intact
grafana_systemd_default_port:
  file.replace:
    - name: /etc/default/grafana-server
    - pattern: '^GF_SERVER_HTTP_PORT=.*'
    - repl: 'GF_SERVER_HTTP_PORT={{ grafana["port"] }}'
    - append_if_not_found: True
    - backup: False
    - require:
      - pkg: grafana_systemd_pkg

grafana_systemd_default_admin_password:
  file.replace:
    - name: /etc/default/grafana-server
    - pattern: '^GF_SECURITY_ADMIN_PASSWORD=.*'
    - repl: 'GF_SECURITY_ADMIN_PASSWORD={{ grafana["admin_password"] }}'
    - append_if_not_found: True
    - backup: False
    - require:
      - pkg: grafana_systemd_pkg

  {%- if grafana["config"] is defined and grafana["config"] is not none %}
grafana_systemd_config:
  file.managed:
    - name: /etc/grafana/grafana.ini
    - user: root
    - group: grafana
    - mode: 640
    - contents: {{ grafana["config"] | yaml_encode }}
    - require:
      - pkg: grafana_systemd_pkg
  {%- endif %}

grafana_systemd_service:
  service.running:
    - name: grafana-server
    - enable: True
    - watch:
      - file: grafana_systemd_default_port
      - file: grafana_systemd_default_admin_password
  {%- if grafana["config"] is defined and grafana["config"] is not none %}
      - file: grafana_systemd_config
  {%- endif %}
    - require:
      - pkg: grafana_systemd_pkg

{% endif %}
