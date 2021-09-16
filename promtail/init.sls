{% if pillar['promtail'] is defined and pillar['promtail'] is not none %}
promtail_data_dir:
  file.directory:
    - name: /opt/promtail/{{ pillar['promtail']['name'] }}/config
    - mode: 755
    - user: 1000
    - group: 0
    - makedirs: True

promtail_config:
  file.managed:
    - name: /opt/promtail/{{ pillar['promtail']['name'] }}/config/config.yaml
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

promtail_image:
  cmd.run:
    - name: docker pull {{ pillar['promtail']['image'] }}

promtail_container:
  docker_container.running:
    - name: promtail-{{ pillar['promtail']['name'] }}
    - user: root
    - image: {{ pillar['promtail']['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - binds:
        - /opt/promtail/{{ pillar['promtail']['name'] }}/config/config.yaml:/etc/promtail/config.yaml
        - /var/log:/var/log
    - watch:
        - /opt/promtail/{{ pillar['promtail']['name'] }}/config/config.yaml
    - command: -config.file=/etc/promtail/config.yaml
{% endif %}