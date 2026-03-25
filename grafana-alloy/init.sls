{% if pillar['grafana-alloy'] is defined and pillar['grafana-alloy'] is not none %}
  {%- if "acme_domain" in pillar["grafana-alloy"] %}
    {%- from "acme/macros.jinja" import verify_and_issue %}
    {%- set acme = pillar["acme"].keys() | first %}
    {{ verify_and_issue(acme, "grafana-alloy", pillar["grafana-alloy"]["acme_domain"]) }}
  {%- endif %}

  {%- set has_config = "config" in pillar["grafana-alloy"] %}
  {%- set has_config_global_part = "config_global_part" in pillar["grafana-alloy"] %}
  {%- set has_config_scrape_parts = "config_scrape_parts" in pillar["grafana-alloy"] %}
  
  {%- if not has_config and (not has_config_global_part or not has_config_scrape_parts) %}

grafana-alloy_config_validation_error:
  test.configurable_test_state:
    - name: invalid_grafana_alloy_config
    - changes: False
    - result: False
    - comment: |
        grafana-alloy: Invalid configuration!
        
        You must provide ONE of the following:
        1. grafana-alloy.config (complete config file)
        OR
        2. BOTH grafana-alloy.config_global_part AND grafana-alloy.config_scrape_parts (with at least one job)

  {%- elif has_config_global_part and not has_config_scrape_parts %}

grafana-alloy_config_validation_error2:
  test.configurable_test_state:
    - name: missing_scrape_parts
    - changes: False
    - result: False
    - comment: |
        grafana-alloy: Invalid configuration!
        
        You set config_global_part but config_scrape_parts is missing.
        If using config_global_part, you MUST also provide config_scrape_parts with at least one job.

  {%- elif has_config_scrape_parts and not has_config_global_part %}

grafana-alloy_config_validation_error3:
  test.configurable_test_state:
    - name: missing_global_part
    - changes: False
    - result: False
    - comment: |
        grafana-alloy: Invalid configuration!
        
        You set config_scrape_parts but config_global_part is missing.
        If using config_scrape_parts, you MUST also provide config_global_part.

  {%- else %}


grafana-alloy_group:
  group.present:
    - name: grafana-alloy
    - system: True

grafana-alloy_user:
  user.present:
    - name: grafana-alloy
    - system: True
    - gid: grafana-alloy
    - home: /opt/grafana-alloy
    - shell: /sbin/nologin
    - createhome: False
    - require:
      - group: grafana-alloy_group

{%- if grains['os_family'] in ('Debian', 'RedHat') %}

grafana-alloy_docker_group_add:
  cmd.run:
    - name: getent group docker > /dev/null && usermod -aG docker grafana-alloy || true
    - require:
      - user: grafana-alloy_user

{%- endif %}


grafana-alloy_data_dirs:
  file.directory:
    - names:
      - /opt/grafana-alloy/bin
      - /opt/grafana-alloy/data
      - /opt/grafana-alloy/etc
    - mode: 755
    - user: grafana-alloy
    - group: grafana-alloy
    - makedirs: True
    - require:
      - user: grafana-alloy_user


grafana-env-file:
  file.managed:
    - name: /etc/default/alloy
    - mode: 644
    - contents: |
        ## Path:
        ## Description: Grafana Alloy settings
        ## Type:        string
        ## Default:     ""
        ## ServiceRestart: grafana-alloy
        #
        # Command line options for Grafana Alloy.
        #
        # The configuration file holding the Grafana Alloy config.
        CONFIG_FILE="/opt/grafana-alloy/etc/config.alloy"

        # User-defined arguments to pass to the run command.
        CUSTOM_ARGS="--server.http.listen-addr=0.0.0.0:12345"

        # Restart on system upgrade. Defaults to true.
        RESTART_ON_UPGRADE=true

    {%- if "config" in pillar["grafana-alloy"] %}

grafana-alloy_config:
  file.managed:
    - name: /opt/grafana-alloy/etc/config.alloy
    - mode: 644
    - user: grafana-alloy
    - group: grafana-alloy
    - require:
      - file: grafana-alloy_data_dirs
    - contents: |
        {{ pillar['grafana-alloy']['config'] | indent(8) }}

    {%- else %}
      {%- set scrape_fragments = [] %}
      {%- for part_name in pillar["grafana-alloy"]["config_scrape_parts"].keys() | sort %}
        {%- set _ = scrape_fragments.append(pillar["grafana-alloy"]["config_scrape_parts"][part_name]) %}
      {%- endfor %}
      {%- set merged_scrape_text = scrape_fragments | join('\n') %}


grafana-alloy_config:
  file.managed:
    - name: /opt/grafana-alloy/etc/config.alloy
    - mode: 644
    - user: grafana-alloy
    - group: grafana-alloy
    - require:
      - file: grafana-alloy_data_dirs
    - contents: |
        {{ pillar['grafana-alloy']['config_global_part'] | indent(8) }}
        
        {{ merged_scrape_text | indent(8) }}

    {%- endif %}


grafana-alloy_binary_1:
  archive.extracted:
    - name: /opt/grafana-alloy/bin
    - source: {{ pillar['grafana-alloy']['binary']['link'] }}
    - user: 0
    - group: 0
    - enforce_toplevel: False
    - skip_verify: True
    - require:
      - file: grafana-alloy_data_dirs

grafana-alloy_binary_2:
  file.rename:
    - name: /opt/grafana-alloy/bin/alloy
    - source: /opt/grafana-alloy/bin/alloy-linux-amd64
    - force: True
    - require:
      - archive: grafana-alloy_binary_1

grafana-alloy_binary_3:
  file.managed:
    - name: /opt/grafana-alloy/bin/alloy
    - mode: 755
    - replace: False
    - require:
      - file: grafana-alloy_binary_2

grafana-alloy_systemd_1:
  file.managed:
    - name: /etc/systemd/system/grafana-alloy.service
    - user: 0
    - group: 0
    - mode: 644
    - contents: |
        [Unit]
        Description=Vendor-agnostic OpenTelemetry Collector distribution with programmable pipelines
        Documentation=https://grafana.com/docs/alloy
        Wants=network-online.target
        After=network-online.target
        
        [Service]
        Restart=always
        User=grafana-alloy
        Group=grafana-alloy
        Environment=HOSTNAME=%H
        Environment=ALLOY_DEPLOY_MODE=binary
        EnvironmentFile=-/etc/default/alloy
        WorkingDirectory=/opt/grafana-alloy/data
        ExecStart=/opt/grafana-alloy/bin/alloy run $CUSTOM_ARGS --storage.path=/opt/grafana-alloy/data $CONFIG_FILE
        ExecReload=/usr/bin/env kill -HUP $MAINPID
        TimeoutStopSec=20s
        SendSIGKILL=no
        CapabilityBoundingSet=CAP_DAC_READ_SEARCH
        AmbientCapabilities=CAP_DAC_READ_SEARCH
        
        [Install]
        WantedBy=multi-user.target

systemd-reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: grafana-alloy_systemd_1

  {%- if pillar['grafana-alloy'].get('disable_promtail', False) %}

    {# On CentOS 7 (Python 3.6) service.running fails due to capture_output bug,
       using cmd.run as a workaround #}
    {%- if grains['os'] == 'CentOS' and grains['osmajorrelease'] == 7 %}
promtail_service_disabled:
  cmd.run:
    - name: systemctl disable promtail && systemctl stop promtail
    - onlyif: systemctl is-active promtail || systemctl is-enabled promtail
    {%- else %}
promtail_service_disabled:
  service.dead:
    - name: promtail
    - enable: False
    {%- endif %}

  {%- endif %}

    {# On CentOS 7 (Python 3.6) service.running fails due to capture_output bug,
       using cmd.run as a workaround #}
    {%- if grains['os'] == 'CentOS' and grains['osmajorrelease'] == 7 %}
grafana-alloy_systemd_2:
  cmd.run:
    - name: systemctl enable grafana-alloy && systemctl start grafana-alloy
    - unless: systemctl is-active grafana-alloy
    - require:
      - file: grafana-alloy_systemd_1
      - cmd: systemd-reload
    {%- if pillar['grafana-alloy'].get('disable_promtail', False) %}
      - cmd: promtail_service_disabled
    {%- endif %}
    {%- else %}
grafana-alloy_systemd_3:
  service.running:
    - name: grafana-alloy
    - enable: True
    - require:
      - file: grafana-alloy_systemd_1
      - cmd: systemd-reload
    {%- if pillar['grafana-alloy'].get('disable_promtail', False) %}
      - service: promtail_service_disabled
    {%- endif %}
    {%- endif %}

grafana-alloy_systemd_4:
  cmd.run:
    - name: systemctl restart grafana-alloy
    - onchanges:
      - file: grafana-alloy_systemd_1
      - file: grafana-env-file
      - file: grafana-alloy_config
    - require:
    {%- if grains['os'] == 'CentOS' and grains['osmajorrelease'] == 7 %}
      - cmd: grafana-alloy_systemd_2
    {%- else %}
      - service: grafana-alloy_systemd_3
    {%- endif %}

  {%- endif %}
{% endif %} 
