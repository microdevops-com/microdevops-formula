{% if pillar['promtail'] is defined and pillar['promtail'] is not none %}

  {% if pillar["promtail"]["scrape_configs"] is defined and pillar["promtail"]["config"] is defined %}

pillar must contain either "promtail.config" or "promtail.scrape_configs" block:
  test.fail_without_changes:
    - name: Pillar must contain either "promtail.config" or "promtail.scrape_configs" block.

  {% else %}

promtail_data_dirs:
  file.directory:
    - names:
      - /opt/promtail/etc/systemd
      - /opt/promtail/bin
    - mode: 755
    - user: 0
    - group: 0
    - makedirs: True

    {% if pillar["promtail"]["scrape_configs"] is defined %}
promtail_config:
  file.managed:
    - name: /opt/promtail/etc/promtail.yaml
    - source: salt://promtail/files/config.jinja
    - user: 0
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
    {% elif pillar["promtail"]["config"] is defined %}
      {% if pillar["promtail"]["loki"] is defined or pillar["promtail"]["positions"] is defined %}
when pillar contain "pillar.config" block:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - warnings: |
        When pillar contain "promtail.config" block, the "promtail.positions", "promtail.loki" blocks are IGNORED
      {% endif %}
promtail_config:
  file.serialize:
    - name: /opt/promtail/etc/promtail.yaml
    - user: 0
    - group: 0
    - mode: 644
    - serializer: yaml
    - dataset_pillar: promtail:config
    - serializer_opts:
      - sort_keys: False
    {% endif %}

    {% if 'docker' in pillar['promtail'] %}
promtail_image:
  cmd.run:
    - name: docker pull {{ pillar['promtail']['docker']['image'] }}

promtail_container:
  docker_container.running:
    - name: promtail-{{ host }}
    - user: root
    - image: {{ pillar['promtail']['docker']['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - 127.0.0.1:9080:9080/tcp
    - binds:
        - /opt/promtail/etc/promtail.yaml:/etc/promtail/promtail.yaml
    {%- for bind in pillar['promtail']['docker']['binds'] %}
        - {{ bind['bind'] }}
    {%- endfor %}
    - watch:
        - /opt/promtail/etc/promtail.yaml
    - command: -config.file=/etc/promtail/promtail.yaml
    {% else %}

{#
nginx_cert:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["promtail"]["acme_account"] }}/verify_and_issue.sh promtail {{ host }}"
#}

promtail_binary_1:
  archive.extracted:
    - name: /opt/promtail/bin
    - source: {{ pillar['promtail']['binary']['link'] }}
    - user: 0
    - group: 0
    - enforce_toplevel: False
    - skip_verify: True

promtail_binary_2:
  file.rename:
    - name: /opt/promtail/bin/promtail
    - source: /opt/promtail/bin/promtail-linux-amd64
    - force: True

promtail_systemd_1:
  file.managed:
    - name: /etc/systemd/system/promtail.service
    - user: 0
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

{#
promtail_systemd_2:
  file.symlink:
    - name: /etc/systemd/system/promtail.service
    - target: /opt/promtail/etc/systemd/promtail.service
#}

systemd-reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: /etc/systemd/system/promtail.service

promtail_systemd_3:
  service.running:
    - name: promtail
    - enable: True

promtail_systemd_4:
  cmd.run:
    - name: systemctl restart promtail
    - onchanges:
      - file: /etc/systemd/system/promtail.service
      - file: /opt/promtail/etc/promtail.yaml
    {% endif %}
  {% endif %}
{% endif %}
