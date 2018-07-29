{% if pillar['rsnapshot_backup'] is defined and pillar['rsnapshot_backup'] is not none %}

  {%- for host, host_backups in pillar['rsnapshot_backup'].items()|sort %}

    {%- set host_loop = loop %}
    {%- for backup in host_backups['backups'] %}

      # Find myself in the list of backups
      {%- if grains['fqdn'] == backup['host'] %}

rsnapshot_backup_dir_{{ host_loop.index }}_{{ loop.index }}:
  file.directory:
    - name: /opt/sysadmws/rsnapshot_backup
    - user: root
    - group: root
    - mode: 775
    - makedirs: True

rsnapshot_backup_conf_{{ host_loop.index }}_{{ loop.index }}:
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
        {%- for data in host_backups['data'] %}
          {%- for source in data['sources'] %}
        - connect: {{ backup['connect'] if backup['connect'] is defined else host }}
          type: {{ data['type'] }}
          source: {{ source }}
          path: {{ backup['path'] }}
          {%- endfor  %}
        {%- endfor  %}

      {%- endif %}
    {%- endfor %}
  {%- endfor %}

{% endif %}
