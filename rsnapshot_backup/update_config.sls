{% if pillar['rsnapshot_backup'] is defined and pillar['rsnapshot_backup'] is not none and pillar['rsnapshot_backup']['sources'] is defined and pillar['rsnapshot_backup']['sources'] is not none %}

# We don't know yet if there will be backups for this host as backup host, but start creating dir and config.
# This is done to make things simplier and not to accumulate pillars in separate dict.
rsnapshot_backup_dir:
  file.directory:
    - name: /opt/sysadmws/rsnapshot_backup
    - user: root
    - group: root
    - mode: 775
    - makedirs: True

rsnapshot_backup_conf:
  file.serialize:
    - name: /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.conf
    - user: root
    - group: root
    - mode: 660
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: json
    - dataset:
        - enabled: False # The first item in the dataset list is always empty, just to have at least somthing in the list, if no backups found (empty datase produces errors)
          comment: This file is managed by Salt, local changes will be overwritten.
  {%- for host, host_backups in pillar['rsnapshot_backup']['sources'].items()|sort %}
    {%- for host_backups_item in host_backups %}
      {%- for backup in host_backups_item['backups'] %}
        {%- if grains['fqdn'] == backup['host'] %}
          {%- for source in host_backups_item['data'] %}
        - enabled: True
          connect: {{ backup['connect'] if backup['connect'] is defined else host }}
          host: {{ host }}
          type: {{ host_backups_item['type'] }}
          source: {{ source }}
          validate_hostname: {{ host_backups_item['validate_hostname']|default(True) }}
          postgresql_noclean: {{ host_backups_item['postgresql_noclean']|default(False) }}
          mysql_noevents: {{ host_backups_item['mysql_noevents']|default(False) }}
          path: {{ backup['path'] }}
            {%- if host_backups_item['retain_hourly'] is defined and host_backups_item['retain_hourly'] is not none %}
          retain_hourly: {{ host_backups_item['retain_hourly'] }}
            {%- endif %}
            {%- if host_backups_item['retain_daily'] is defined and host_backups_item['retain_daily'] is not none %}
          retain_daily: {{ host_backups_item['retain_daily'] }}
            {%- endif %}
            {%- if host_backups_item['retain_weekly'] is defined and host_backups_item['retain_weekly'] is not none %}
          retain_weekly: {{ host_backups_item['retain_weekly'] }}
            {%- endif %}
            {%- if host_backups_item['retain_monthly'] is defined and host_backups_item['retain_monthly'] is not none %}
          retain_monthly: {{ host_backups_item['retain_monthly'] }}
            {%- endif %}
            {%- if host_backups_item['rsync_args'] is defined and host_backups_item['rsync_args'] is not none %}
          rsync_args: {{ host_backups_item['rsync_args'] }}
            {%- endif %}
            {%- if host_backups_item['connect_user'] is defined and host_backups_item['connect_user'] is not none %}
          connect_user: {{ host_backups_item['connect_user'] }}
            {%- endif %}
            {%- if host_backups_item['connect_password'] is defined and host_backups_item['connect_password'] is not none %}
          connect_password: {{ host_backups_item['connect_password'] }}
            {%- endif %}
            {%- if host_backups_item['checks'] is defined and host_backups_item['checks'] is not none %}
          checks:
              {%- for check in host_backups_item['checks'] %}
            - type: {{ check['type'] }}
                {%- if check['empty_db'] is defined and check['empty_db'] is not none %}
              empty_db: {{ check['empty_db'] }}
                {%- endif %}
                {%- if check['min_file_size'] is defined and check['min_file_size'] is not none %}
              min_file_size: {{ check['min_file_size'] }}
                {%- endif %}
                {%- if check['file_type'] is defined and check['file_type'] is not none %}
              file_type: {{ check['file_type'] }}
                {%- endif %}
                {%- if check['last_file_age'] is defined and check['last_file_age'] is not none %}
              last_file_age: {{ check['last_file_age'] }}
                {%- endif %}
                {%- if check['files_total'] is defined and check['files_total'] is not none %}
              files_total: {{ check['files_total'] }}
                {%- endif %}
                {%- if check['files_mask'] is defined and check['files_mask'] is not none %}
              files_mask: {{ check['files_mask'] }}
                {%- endif %}
              {%- endfor %}
            {%- endif %}
          {%- endfor  %}
        {%- endif  %}
      {%- endfor %}
    {%- endfor %}
  {%- endfor %}

{% endif %}
