{#-
  PMM 3: alert dashboards + Grafana Unified Alerting (file provisioning) + Telegram relay.

  Host layout (pmm3:srv_path is mounted into the PMM container as /srv, see server.sls):
    <srv_path>/grafana/provisioning/alerting/salt-*.yaml  - contact point, policy, rules
                                                            (PMM's own pmm-builtin.json lives there too - not touched)
    <srv_path>/grafana/dashboards/<folder>/<subject>.json - dashboards (Salt owns the directory)
    <telegram_relay:path>/relay.py, relay.env             - Telegram relay: Grafana -> webhook -> relay -> Telegram,
                                                            one post per alert (panel image + text as caption)
-#}
{%- if pillar['pmm3'] is defined and pillar['pmm3'].get('alerting') %}
{%- from 'pmm3/map.jinja' import pmm3 with context %}
{%- from 'pmm3/alerts.jinja' import dashboards, rule_groups with context %}
{%- set alerting_dir = pmm3['srv_path'] ~ '/grafana/provisioning/alerting' %}
{%- set dashboards_dir = pmm3['srv_path'] ~ '/grafana/dashboards' %}
{%- set tg = pmm3['alerting']['telegram'] %}
{%- set relay = pmm3['alerting']['telegram_relay'] %}
{%- set policy = pmm3['alerting']['policy'] %}

{#- PMM runs as uid 1000 gid 0 and owns /srv; it also resets the alerting dir to 775 on every start #}
pmm3_alerting_dirs:
  file.directory:
    - names:
      - {{ pmm3['srv_path'] }}/grafana/provisioning
      - {{ dashboards_dir }}
    - user: {{ pmm3['srv_user'] }}
    - group: {{ pmm3['srv_group'] }}
    - mode: 755
    - makedirs: True

pmm3_alerting_provisioning_dir:
  file.directory:
    - name: {{ alerting_dir }}
    - user: {{ pmm3['srv_user'] }}
    - group: {{ pmm3['srv_group'] }}
    - mode: 775
    - require:
      - file: pmm3_alerting_dirs

pmm3_telegram_relay_script:
  file.managed:
    - name: {{ relay['path'] }}/relay.py
    - source: salt://pmm3/files/telegram-relay/relay.py
    - mode: 644
    - makedirs: True

pmm3_telegram_relay_env:
  file.managed:
    - name: {{ relay['path'] }}/relay.env
    - mode: 600
    - show_changes: False
    - makedirs: True
    - contents: |
        TG_BOT_TOKEN={{ tg['bottoken'] }}
        TG_CHAT_ID={{ tg['chatid'] }}
        TG_THREAD_ID={{ tg.get('message_thread_id', '') }}
        {%- if tg.get('api_url') %}
        TG_API_URL={{ tg['api_url'] }}
        {%- endif %}
        RELAY_AUTH_TOKEN={{ relay['auth_token'] }}
        GRAFANA_URL={{ relay['grafana_url'] }}
        {%- if relay.get('grafana_token') %}
        GRAFANA_TOKEN={{ relay['grafana_token'] }}
        {%- else %}
        GRAFANA_USER=admin
        GRAFANA_PASSWORD={{ pmm3['admin_password'] }}
        {%- endif %}
        GRAFANA_INSECURE_TLS=1
        RENDER_RANGE={{ relay['render_range'] }}
        RENDER_TZ={{ relay['render_tz'] }}
        RESOLVED_IMAGES={{ '1' if relay['resolved_images'] else '0' }}
        LINK_TEXT={{ relay['link_text'] }}

{#- the relay reads relay.env itself (RELAY_ENV_FILE): secrets stay out of `docker inspect` and the state output #}
pmm3_telegram_relay_container:
  cmd.run:
    - name: docker pull {{ relay['image'] }}
    - unless: docker image inspect {{ relay['image'] }} > /dev/null
  docker_container.running:
    - name: pmm3-telegram-relay
    - image: {{ relay['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - command: python -u /app/relay.py
    - environment:
      - RELAY_ENV_FILE: /app/relay.env
    - binds:
      - {{ relay['path'] }}/relay.py:/app/relay.py:ro
      - {{ relay['path'] }}/relay.env:/app/relay.env:ro
    - networks:
      - {{ pmm3['network'] }}:
        - aliases:
          - telegram-relay
    - require:
      - cmd: pmm3_telegram_relay_container
    - watch:
      - file: pmm3_telegram_relay_script
      - file: pmm3_telegram_relay_env

pmm3_alerting_contact_points:
  file.serialize:
    - name: {{ alerting_dir }}/salt-contact-points.yaml
    - mode: 644
    - formatter: yaml
    - show_changes: False  {#- webhook secret #}
    - require:
      - file: pmm3_alerting_provisioning_dir
    - dataset:
        apiVersion: 1
        contactPoints:
          - orgId: 1
            name: telegram
            receivers:
              {#- provisioning never deletes: changing this uid leaves the old receiver alive (duplicate
                  notifications) unless it is listed in deleteContactPoints #}
              - uid: salt-telegram-relay
                type: webhook
                disableResolveMessage: False
                settings:
                  url: {{ relay['url'] }}
                  httpMethod: POST
                  authorization_scheme: Bearer
                  authorization_credentials: {{ relay['auth_token'] | json }}
        policies:
          - orgId: 1
            receiver: telegram
            {#- rulename is set only on DatasourceNoData/DatasourceError - otherwise those of different rules are merged #}
            group_by: {{ policy['group_by'] | json }}
            group_wait: {{ policy['group_wait'] }}
            group_interval: {{ policy['group_interval'] }}
            repeat_interval: {{ policy['repeat_interval'] }}

pmm3_alerting_rules:
  file.serialize:
    - name: {{ alerting_dir }}/salt-rules.yaml
    - mode: 644
    - formatter: yaml
    - require:
      - file: pmm3_alerting_provisioning_dir
    - dataset: {{ {'apiVersion': 1, 'groups': rule_groups} | json }}

{#- folder dirs are declared explicitly, otherwise clean removes them as "extra" #}
{%- set folder_dirs = [] %}
{%- for dashboard in dashboards %}
  {%- set dir = dashboard['path'].rsplit('/', 1)[0] %}
  {%- if dir not in folder_dirs %}{% do folder_dirs.append(dir) %}{% endif %}
{%- endfor %}
{%- for dir in folder_dirs %}

pmm3_dashboards_folder_{{ dir }}:
  file.directory:
    - name: {{ dir }}
    - user: {{ pmm3['srv_user'] }}
    - group: {{ pmm3['srv_group'] }}
    - mode: 755
    - require:
      - file: pmm3_alerting_dirs
    - require_in:
      - file: pmm3_dashboards_clean
{%- endfor %}
{%- for dashboard in dashboards %}

pmm3_dashboard_{{ dashboard['path'] }}:
  file.serialize:
    - name: {{ dashboard['path'] }}
    - mode: 644
    - formatter: json
    - require:
      - file: pmm3_dashboards_folder_{{ dashboard['path'].rsplit('/', 1)[0] }}
    - require_in:
      - file: pmm3_dashboards_clean
    - dataset: {{ dashboard['data'] | json }}
{%- endfor %}

{#- remove dashboards that are no longer in pillar #}
pmm3_dashboards_clean:
  file.directory:
    - name: {{ dashboards_dir }}
    - clean: True

{#- reload provisioning without a restart; if Grafana is down (first start) it picks the files up on start.
    The stamp (md5 of the provisioned files) is written after a successful reload, so a failed reload is retried
    on the next run instead of being lost with onchanges #}
{%- set stamp = pmm3['provisioning_path'] ~ '/.alerting-reload.md5' %}
{%- set checksums = 'find ' ~ dashboards_dir ~ ' ' ~ alerting_dir ~ ' -type f \\( -name "*.json" -o -name "salt-*.yaml" \\) | sort | xargs -r md5sum' %}
pmm3_alerting_reload:
  cmd.run:
    - name: |
        curl -sSfk -u "$PMM_AUTH" -X POST {{ pmm3['api_url'] }}/api/admin/provisioning/dashboards/reload && echo &&
        curl -sSfk -u "$PMM_AUTH" -X POST {{ pmm3['api_url'] }}/api/admin/provisioning/alerting/reload && echo &&
        {{ checksums }} > {{ stamp }}
    - shell: /bin/bash
    - env:
      - PMM_AUTH: {{ ('admin:' ~ pmm3['admin_password']) | json }}
    {#- skip when Grafana is down or nothing changed since the last successful reload #}
    - unless: '! curl -sfk -o /dev/null {{ pmm3['api_url'] }}/api/health || diff -q {{ stamp }} <({{ checksums }}) > /dev/null 2>&1'
    - require:
      - file: pmm3_alerting_contact_points
      - file: pmm3_alerting_rules
      - file: pmm3_dashboards_clean
{%- endif %}
