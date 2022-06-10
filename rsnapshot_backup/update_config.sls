{% if grains["os"] == "Windows" %}
update_config_fail:
  test.configurable_test_state:
    - name: update_config_fail
    - changes: False
    - result: False
    - comment: |
         NOTICE: update_config is not for Windows, probably you run rsnapshot_backup pipeline for Windows server - it is wrong.

{% elif pillar["rsnapshot_backup"] is defined and "sources" in pillar["rsnapshot_backup"] %}

rsnapshot_backup_dir:
  file.directory:
    - name: /opt/sysadmws/rsnapshot_backup
    - user: root
    - group: root
    - mode: 775
    - makedirs: True

  # Collect host_backups_items respecting priority
  {% set host_backups_items = [] %}
  {%- for host, host_backups in pillar["rsnapshot_backup"]["sources"].items()|sort %}
    {%- for host_backups_item in host_backups %}
      {%- if host_backups_item["type"] != "SUPPRESS_COVERAGE" %}
        {%- for backup in host_backups_item["backups"] %}
          {%- if grains["id"] == backup["host"] %}
            {%- if backup["priority"] is defined %}
              {%- do host_backups_item.update({"_priority": backup["priority"]|int}) %}
            {%- else  %}
              {%- do host_backups_item.update({"_priority": 0}) %}
            {%- endif  %}
            {%- do host_backups_item.update({"_host": host}) %}
            {%- do host_backups_items.append(host_backups_item) %}
          {%- endif  %}
        {%- endfor %}
      {%- endif  %}
    {%- endfor %}
  {%- endfor %}

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
        - enabled: False # The first item in the dataset list is always empty, just to have at least somthing in the list, if no backups found (empty dataset produces errors)
          comment: This file is managed by Salt, local changes will be overwritten.
  {%- include "rsnapshot_backup/update_config.jinja" with context %}

rsnapshot_backup_yaml:
  file.serialize:
    - name: /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.yaml
    - user: root
    - group: root
    - mode: 660
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: yaml
    - serializer_opts:
      - width: 10240 # otherwise it will split long commands in multiple lines
    - dataset:
        - enabled: False # The first item in the dataset list is always empty, just to have at least somthing in the list, if no backups found (empty dataset produces errors)
          comment: This file is managed by Salt, local changes will be overwritten.
  {%- include "rsnapshot_backup/update_config.jinja" with context %}

{% else %}
rsnapshot_backup_dir:
  file.directory:
    - name: /opt/sysadmws/rsnapshot_backup
    - user: root
    - group: root
    - mode: 775
    - makedirs: True

  # Just empty config if not exists - not to overwrite manually created config

  {%- if not salt["file.file_exists"]("/opt/sysadmws/rsnapshot_backup/rsnapshot_backup.conf") %}
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
        - enabled: False # The first item in the dataset list is always empty, just to have at least somthing in the list, if no backups found (empty dataset produces errors)
          comment: This file is managed by Salt, local changes will be overwritten.

  {%- endif %}

  {%- if not salt["file.file_exists"]("/opt/sysadmws/rsnapshot_backup/rsnapshot_backup.yaml") %}
rsnapshot_backup_yaml:
  file.serialize:
    - name: /opt/sysadmws/rsnapshot_backup/rsnapshot_backup.yaml
    - user: root
    - group: root
    - mode: 660
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: yaml
    - dataset:
        - enabled: False # The first item in the dataset list is always empty, just to have at least somthing in the list, if no backups found (empty dataset produces errors)
          comment: This file is managed by Salt, local changes will be overwritten.

  {%- endif %}

{% endif %}
