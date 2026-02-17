{% if pillar['promtail'] is defined and pillar['promtail'] is not none %}
  {%- if "acme_domain" in pillar["promtail"] %}
    {%- from "acme/macros.jinja" import verify_and_issue %}
    {%- set acme = pillar["acme"].keys() | first %}
    {{ verify_and_issue(acme, "promtail", pillar["promtail"]["acme_domain"]) }}
  {%- endif %}

  {%- if pillar["promtail"]["scrape_configs"] is defined and pillar["promtail"]["config"] is defined %}

pillar must contain either "promtail.config" or "promtail.scrape_configs" block:
  test.fail_without_changes:
    - name: Pillar must contain either "promtail.config" or "promtail.scrape_configs" block.

  {%- else %}

promtail_data_dirs:
  file.directory:
    - names:
      - /opt/promtail/etc/systemd
      - /opt/promtail/bin
    - mode: 755
    - user: 0
    - group: 0
    - makedirs: True

    {# ================================================================
       NEW PATH: config_global_part + config_scrape_parts (dict)
       - config_global_part: string — top of promtail.yaml (server, clients, limits…)
       - config_scrape_parts: dict — each key is a unique name, value is a YAML
         string with one or more `- job_name: …` blocks.
         Salt deep-merges dicts, so multiple pillar SLS files each add their
         own key and they all end up here.
         If config_scrape_parts is empty or absent, a warning is issued and Promtail will not be deployed.
       ================================================================ #}
    {%- set config_deployed = { 'is_ready': false } %}
    {%- if "config_global_part" in pillar["promtail"] %}
      {%- set scrape_fragments = [] %}
      {%- if "config_scrape_parts" in pillar["promtail"] %}
        {%- for part_name in pillar["promtail"]["config_scrape_parts"].keys() | sort %}
          {%- set _ = scrape_fragments.append(pillar["promtail"]["config_scrape_parts"][part_name]) %}
        {%- endfor %}
      {%- endif %}
      {%- if scrape_fragments | length == 0 %}

promtail_no_scrape_jobs:
  test.configurable_test_state:
    - name: no_scrape_jobs_attached
    - changes: False
    - result: True
    - warnings: |
        promtail: config_global_part is set but no config_scrape_parts jobs are attached.
        Promtail config will NOT be deployed until at least one job pillar is connected via top_sls.

      {%- else %}
      {%- set merged_scrape_text = scrape_fragments | join('\n') %}
      {%- set _ = config_deployed.update({'is_ready': true}) %}

promtail_config:
  file.managed:
    - name: /opt/promtail/etc/promtail.yaml
    - mode: 644
    - user: 0
    - group: 0
    - contents: |
        {{ pillar['promtail']['config_global_part'] | indent(8) }}
        scrape_configs:
        {{ merged_scrape_text | indent(8) }}
      {%- endif %}

    {# ================================================================
       LEGACY PATH 1: promtail.scrape_configs (uses config.jinja template)
       ================================================================ #}
    {%- elif pillar["promtail"]["scrape_configs"] is defined %}
      {%- set _ = config_deployed.update({'is_ready': true}) %}
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

    {# ================================================================
       LEGACY PATH 2: promtail.config (full config verbatim)
       ================================================================ #}
    {%- elif pillar["promtail"]["config"] is defined %}
      {%- set _ = config_deployed.update({'is_ready': true}) %}
      {%- if pillar["promtail"]["loki"] is defined or pillar["promtail"]["positions"] is defined %}
when pillar contain "pillar.config" block:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - warnings: |
        When pillar contain "promtail.config" block, the "promtail.positions", "promtail.loki" blocks are IGNORED
      {%- endif %}
promtail_config:
  file.managed:
    - name: /opt/promtail/etc/promtail.yaml
    - mode: 644
    - user: 0
    - group: 0
    - contents: |
        {{ pillar['promtail']['config'] | indent(8) }}
    {%- endif %}

    {%- if config_deployed['is_ready'] and 'docker' in pillar['promtail'] %}
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
    {%- elif config_deployed['is_ready'] %}

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

systemd-reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: /etc/systemd/system/promtail.service

    {# On CentOS 7 (Python 3.6) service.running fails due to capture_output bug,
       using cmd.run as a workaround #}
    {%- if grains['os'] == 'CentOS' and grains['osmajorrelease'] == 7 %}
promtail_systemd_3:
  cmd.run:
    - name: systemctl enable promtail && systemctl start promtail
    - unless: systemctl is-active promtail
    {%- else %}
promtail_systemd_3:
  service.running:
    - name: promtail
    - enable: True
    {%- endif %}

promtail_systemd_4:
  cmd.run:
    - name: systemctl restart promtail
    - onchanges:
      - file: /etc/systemd/system/promtail.service
      - file: /opt/promtail/etc/promtail.yaml
    {%- endif %}
  {%- endif %}
{% endif %}

