{% if pillar['loki'] is defined and pillar['loki'] is not none %}
  {% if pillar["loki"]["nginx_gateway"] | default(false) %}
    {% include "loki/gateway.sls" with context %}
  {% else %}
loki_dirs:
  file.directory:
    - names:
      - /opt/loki/etc
      - /opt/loki/bin
    - mode: 755
    - user: 0
    - group: 0
    - makedirs: True

loki_config:
  file.serialize:
    - name: /opt/loki/etc/config.yaml
    - user: 0
    - group: 0
    - mode: 644
    - serializer: yaml
    - dataset_pillar: loki:config
    - serializer_opts:
      - sort_keys: False

loki_binary:
  archive.extracted:
    - name: /opt/loki/bin
    - source: {{ pillar['loki']['binary']['link'] }}
    - user: 0
    - group: 0
    - enforce_toplevel: False
    - skip_verify: True
  file.rename:
    - name: /opt/loki/bin/loki
    - source: /opt/loki/bin/loki-linux-amd64
    - force: True

loki_systemd_1:
  file.managed:
    - name: /etc/systemd/system/loki.service
    - user: 0
    - group: 0
    - mode: 644
    - contents: |
        [Unit]
        Description=Loki Service
        After=network.target
        [Service]
        Type=simple
        ExecStart=/opt/loki/bin/loki -config.file /opt/loki/etc/config.yaml {% if 'extra_args' in pillar['loki'] -%} {{ pillar['loki']['extra_args'] }} {%- endif %}
        ExecReload=/bin/kill -HUP $MAINPID
        Restart=on-failure
        [Install]
        WantedBy=multi-user.target

systemd-reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: /etc/systemd/system/loki.service

loki_systemd_3:
  service.running:
    - name: loki
    - enable: True

loki_systemd_4:
  cmd.run:
    - name: systemctl restart loki
  {% endif %}
{% endif %}
