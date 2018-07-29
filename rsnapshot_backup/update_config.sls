{% if pillar['rsnapshot_backup'] is defined and pillar['rsnapshot_backup'] is not none %}

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
  {%- for host, host_backups in pillar['rsnapshot_backup'].items()|sort %}
    {%- set host_loop = loop %}
    {%- for backup in host_backups['backups'] %}
      {%- if grains['fqdn'] == backup['host'] %}
        {%- for data in host_backups['data'] %}
          {%- for source in data['sources'] %}
        - enabled: True
          connect: {{ backup['connect'] if backup['connect'] is defined else host }}
          type: {{ data['type'] }}
          source: {{ source }}
          path: {{ backup['path'] }}
          {%- endfor  %}
        {%- endfor  %}
      {%- endif %}
    {%- endfor %}
  {%- endfor %}

{% endif %}
