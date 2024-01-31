{%- for loki_name, loki_data in pillar.get("loki",{}).items() %}
  {%- set loki_name_o = loki_name %}
  {%- set loki_name = loki_name.replace(".","_") %}

  {% if loki_data.get("nginx",{}).get("enabled", True) %}
    {% include "loki/nginx/nginx.sls" with context %}
  {% endif %}

  {% if not loki_data["nginx"].get("gateway", False) %}
    {% set path_prefix = loki_data["path_prefix"].replace("__NAME__", loki_name_o)%}
loki_{{ loki_name }}_dirs:
  file.directory:
    - names:
      - {{ path_prefix }}/etc
      - {{ path_prefix }}/bin
    - mode: 755
    - user: 0
    - group: 0
    - makedirs: True

loki_{{ loki_name }}_config:
  file.serialize:
    - name: {{ path_prefix }}/etc/config.yaml
    - user: 0
    - group: 0
    - mode: 644
    - serializer: yaml
    - dataset: {{ loki_data["config"] | tojson | replace("__PATH_PREFIX__", path_prefix) | load_json }}
    - serializer_opts:
      - sort_keys: False

loki_{{ loki_name }}_binary:
  archive.extracted:
    - name: {{ path_prefix }}/bin
    - source: {{ loki_data["binary"]["link"] }}
    - user: 0
    - group: 0
    - enforce_toplevel: False
    - skip_verify: True
  file.rename:
    - name: {{ path_prefix }}/bin/loki
    - source: {{ path_prefix }}/bin/loki-linux-amd64
    - force: True

loki_{{ loki_name }}_systemd_1:
  file.managed:
    - name: /etc/systemd/system/{{ loki_name }}.service
    - user: 0
    - group: 0
    - mode: 644
    - contents: |
        [Unit]
        Description=Loki Service
        After=network.target
        [Service]
        Type=simple
        ExecStart={{ path_prefix }}/bin/loki -config.file {{ path_prefix }}/etc/config.yaml {{ loki_data.get("extra_args","") }}
        ExecReload=/bin/kill -HUP $MAINPID
        Restart=on-failure
        [Install]
        WantedBy=multi-user.target

loki_{{ loki_name }}_systemd-reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: /etc/systemd/system/{{ loki_name }}.service

loki_{{ loki_name }}_systemd_3:
  service.running:
    - name: {{ loki_name }}
    - enable: True

loki_{{ loki_name }}_systemd_4:
  cmd.run:
    - name: systemctl restart {{ loki_name }}
  {% endif %}
{% endfor %}
