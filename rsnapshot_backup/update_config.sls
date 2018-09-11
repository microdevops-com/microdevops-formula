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
          {%- include 'rsnapshot_backup/update_config.jinja' with context %}
        {%- endif  %}
      {%- endfor %}
    {%- endfor %}
  {%- endfor %}

{% endif %}
