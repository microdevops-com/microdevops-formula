{% if pillar['percona-valkey'] is defined and 'sentinel_conf' in pillar['percona-valkey'] %}

{% include "percona-valkey/common-install.sls" with context %}

percona_valkey_sentinel_run:
  service.running:
    - name: valkey-sentinel
    - enable: True

  {%- if not pillar['percona-valkey'].get('keep_existing_conf', True) %}
percona_valkey_sentinel_config:
  file.managed:
    - name: /etc/valkey/sentinel.conf
    - user: valkey
    - group: valkey
    - mode: 640
    - contents: {{ pillar['percona-valkey']['sentinel_conf'] | yaml_encode }}

percona_valkey_sentinel_restart:
  cmd.run:
    - name: systemctl restart valkey-sentinel
    - onchanges:
        - file: /etc/valkey/sentinel.conf
  {%- endif %}
{% endif  %}