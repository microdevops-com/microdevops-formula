{% if pillar['percona-valkey'] is defined and 'valkey_conf' in pillar['percona-valkey'] %}

{% include "percona-valkey/common-install.sls" with context %}

percona_valkey_run:
  service.running:
    - name: valkey
    - enable: True

  {%- if not pillar['percona-valkey'].get('keep_existing_conf', True) %}
percona_valkey_config:
  file.managed:
    - name: /etc/valkey/valkey.conf
    - user: valkey
    - group: valkey
    - mode: 640
    - contents: {{ pillar['percona-valkey']['valkey_conf'] | yaml_encode }}

percona_valkey_restart:
  cmd.run:
    - name: systemctl restart valkey
    - onchanges:
        - file: /etc/valkey/valkey.conf
  {%- endif %}

  {%- if pillar['percona-valkey'].get('disable_thp', False) %}
disable_transparent_hugepage:
  cmd.run:
    - name: 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
    - shell: /bin/bash
  file.managed:
    - name: /etc/tmpfiles.d/disable-thp.conf
    - contents: |
        #    Path                                            Mode UID  GID  Age Argument
        w    /sys/kernel/mm/transparent_hugepage/enabled     -    -    -    -   never
    - mode: 644
    - user: 0
    - group: 0
  {%- endif  %}

  {%- if pillar['percona-valkey'].get('manage_limits', False) %}
{%- set maxclients = pillar['percona-valkey'].get('maxclients', 10000) %}
{%- set nofile_limit = maxclients + 32 %}

set_valkey_systemd_limits:
  file.managed:
    - name: /etc/systemd/system/valkey.service.d/limits.conf
    - user: 0
    - group: 0
    - mode: 644
    - makedirs: True
    - contents: |
        [Service]
        LimitNOFILE={{ nofile_limit }}

reload_systemd_for_valkey:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
        - file: /etc/systemd/system/valkey.service.d/limits.conf

restart_valkey_after_limits:
  cmd.run:
    - name: systemctl restart valkey
    - onchanges:
        - file: /etc/systemd/system/valkey.service.d/limits.conf
    - require:
        - cmd: reload_systemd_for_valkey

set_maxclients_for_valkey_user:
  file.managed:
    - name: /etc/security/limits.d/95-valkey.conf
    - user: 0
    - group: 0
    - mode: 644
    - contents: |
        root soft nofile {{ maxclients }}
        root hard nofile {{ maxclients }}
        valkey soft nofile {{ maxclients }}
        valkey hard nofile {{ maxclients }}
        haproxy soft nofile {{ maxclients * 2 + 100 }}
        haproxy hard nofile {{ maxclients * 2 + 100 }}
  {%- endif  %}
{% endif  %}
