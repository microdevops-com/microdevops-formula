{%- set cfg = pillar.get('cloudflare_log_collector', {}) %}
{%- if cfg.get('enabled', False) %}
{%- set config_dir = cfg.get('config_dir', '/etc/cloudflare-log-collector') %}
{%- set state_dir = cfg.get('state_dir', '/var/lib/cloudflare-log-collector') %}
{%- set log_dir = cfg.get('log_dir', '/var/log/cloudflare') %}
{%- set token_file = cfg.get('token_file', config_dir ~ '/token') %}

cloudflare_log_collector_python:
  pkg.installed:
    - name: {{ cfg.get('python_package', 'python3') }}

cloudflare_log_collector_directories:
  file.directory:
    - names:
      - /usr/local/lib/cloudflare-log-collector
      - {{ config_dir }}
      - {{ state_dir }}
      - {{ log_dir }}
    - user: root
    - group: root
    - mode: '0750'
    - makedirs: True

cloudflare_log_collector_script:
  file.managed:
    - name: /usr/local/lib/cloudflare-log-collector/collector.py
    - source: salt://cloudflare_log_collector/files/collector.py
    - user: root
    - group: root
    - mode: '0755'
    - require:
      - pkg: cloudflare_log_collector_python
      - file: cloudflare_log_collector_directories

cloudflare_log_collector_config:
  file.managed:
    - name: {{ config_dir }}/config.json
    - source: salt://cloudflare_log_collector/files/config.json.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: '0644'
    - context:
        api_base: {{ cfg.get('api_base', 'https://api.cloudflare.com/client/v4') | json }}
        zone_id: {{ cfg.get('zone_id', '') | json }}
        token_file: {{ token_file | json }}
        state_dir: {{ state_dir | json }}
        log_dir: {{ log_dir | json }}
        poll_delay_seconds: {{ cfg.get('poll_delay_seconds', 120) }}
        initial_lookback_seconds: {{ cfg.get('initial_lookback_seconds', 300) }}
        overlap_seconds: {{ cfg.get('overlap_seconds', 120) }}
        slice_seconds: {{ cfg.get('slice_seconds', 60) }}
        firewall_events_slice_seconds: {{ cfg.get('firewall_events_slice_seconds', 300) }}
        min_slice_seconds: {{ cfg.get('min_slice_seconds', 5) }}
        page_size: {{ cfg.get('page_size', 5000) }}
        max_pages_per_slice: {{ cfg.get('max_pages_per_slice', 100) }}
        request_timeout_seconds: {{ cfg.get('request_timeout_seconds', 30) }}
        request_retries: {{ cfg.get('request_retries', 1) }}
        dedup_retention_hours: {{ cfg.get('dedup_retention_hours', 48) }}
    - require:
      - file: cloudflare_log_collector_directories

{%- if cfg.get('token') %}
cloudflare_log_collector_token:
  file.managed:
    - name: {{ token_file }}
    - contents_pillar: cloudflare_log_collector:token
    - user: root
    - group: root
    - mode: '0600'
    - show_changes: False
    - require:
      - file: cloudflare_log_collector_directories
{%- endif %}

cloudflare_log_collector_service:
  file.managed:
    - name: /etc/systemd/system/cloudflare-log-collector.service
    - source: salt://cloudflare_log_collector/files/cloudflare-log-collector.service.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: '0644'
    - context:
        config_file: {{ (config_dir ~ '/config.json') | json }}
        token_file: {{ token_file | json }}
        state_dir: {{ state_dir | json }}
        log_dir: {{ log_dir | json }}
    - require:
      - file: cloudflare_log_collector_script
      - file: cloudflare_log_collector_config

cloudflare_log_collector_timer:
  file.managed:
    - name: /etc/systemd/system/cloudflare-log-collector.timer
    - source: salt://cloudflare_log_collector/files/cloudflare-log-collector.timer.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: '0644'
    - context:
        schedule: {{ cfg.get('schedule', '*:0/5') | json }}
        randomized_delay: {{ cfg.get('randomized_delay', '30s') | json }}

cloudflare_log_collector_logrotate:
  file.managed:
    - name: /etc/logrotate.d/cloudflare-log-collector
    - source: salt://cloudflare_log_collector/files/logrotate.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: '0644'
    - context:
        log_dir: {{ log_dir | json }}
        retention: {{ cfg.get('logrotate_retention', 14) }}

cloudflare_log_collector_systemd_reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: cloudflare_log_collector_service
      - file: cloudflare_log_collector_timer

cloudflare_log_collector_timer_running:
  service.running:
    - name: cloudflare-log-collector.timer
    - enable: True
    - require:
      - cmd: cloudflare_log_collector_systemd_reload
    - watch:
      - file: cloudflare_log_collector_timer

{%- endif %}
