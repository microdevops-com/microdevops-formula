{% if pillar['promtail'] is defined and pillar['promtail'] is not none %}
promtail_data_dirs:
  file.directory:
    - names:
      - /opt/promtail/etc/systemd
      - /opt/promtail/bin
    - mode: 755
    - user: 1000
    - group: 0
    - makedirs: True

promtail_config:
  file.managed:
    - name: /opt/promtail/etc/promtail.yaml
    - source: salt://promtail/files/config.jinja
    - user: 1000
    - group: 0
    - mode: 644
    - template: jinja
    - defaults:
        scrape_configs: |
          - job_name: system
            static_configs:
            - labels:
                job: varlogs
                __path__: /var/log/*log

  {% if pillar['promtail']['docker']['enabled'] == true %}
promtail_image:
  cmd.run:
    - name: docker pull {{ pillar['promtail']['image'] }}

promtail_container:
  docker_container.running:
    - name: promtail-{{ host }}
    - user: root
    - image: {{ pillar['promtail']['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - 0.0.0.0:9080:9080/tcp
    - binds:
        - /opt/promtail/etc/promtail.yaml:/etc/promtail/promtail.yaml
  {%- for bind in pillar['promtail']['docker']['binds'] %}
        - {{ bind['bind'] }}
  {%- endfor %}
    - watch:
        - /opt/promtail/etc/promtail.yaml
    - command: -config.file=/etc/promtail/promtail.yaml
  {% else %}

promtail_binary_1:
  archive.extracted:
    - name: /opt/promtail/bin
    - source: {{ pillar['promtail']['binary']['link'] }}
    - source_hash: {{ pillar['promtail']['binary']['hash'] }}
    - user: 0
    - group: 0
    - enforce_toplevel: False

promtail_binary_2:
  file.rename:
    - name: /opt/promtail/bin/promtail
    - source: /opt/promtail/bin/promtail-linux-amd64
    - force: True

promtail_systemd_1:
  file.managed:
    - name: /opt/promtail/etc/systemd/promtail.service
    - user: 1000
    - group: 0
    - mode: 644
    - contents: |
        [Unit]
        Description=Promtail Service
        After=network.target
        [Service]
        Type=simple
        ExecStart=/opt/promtail/bin/promtail -config.file /opt/promtail/etc/promtail.yaml
        ExecReload=/bin/kill -HUP $MAINPID
        Restart=on-failure
        [Install]
        WantedBy=multi-user.target

promtail_systemd_2:
  file.symlink:
    - name: /etc/systemd/system/promtail.service
    - target: /opt/promtail/etc/systemd/promtail.service

systemd-reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: /opt/promtail/etc/systemd/promtail.service

promtail_systemd_3:
  service.running:
    - name: promtail
    - enable: True

promtail_systemd_4:
  cmd.run:
    - name: systemctl restart promtail
    - onchanges:
      - file: /opt/promtail/etc/systemd/promtail.service

  {% endif %}
{% endif %}
