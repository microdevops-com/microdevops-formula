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
  {%- for host_backups_item in host_backups_items|sort(attribute="_priority") %}
    {%- for backup in host_backups_item["backups"] %}
      {%- if grains["id"] == backup["host"] %}
        {%- for source in host_backups_item["data"] %}
        - enabled: True
          connect: {{ backup["connect"] if backup["connect"] is defined else host_backups_item["_host"] }}
          host: {{ host_backups_item["_host"] }}
          type: {{ host_backups_item["type"] }}
          source: {{ source }}
          validate_hostname: {{ host_backups_item["validate_hostname"]|default(True) }}
          postgresql_noclean: {{ host_backups_item["postgresql_noclean"]|default(False) }}
          mysql_noevents: {{ host_backups_item["mysql_noevents"]|default(False) }}
          native_txt_check: {{ host_backups_item["native_txt_check"]|default(False) }}
          native_10h_limit: {{ host_backups_item["native_10h_limit"]|default(False) }}
          path: {{ backup["path"] }}
          # Retains per backup host override backup item
          {%- if "retain_hourly" in backup %}
          retain_hourly: {{ backup["retain_hourly"] }}
          {%- elif "retain_hourly" in host_backups_item %}
          retain_hourly: {{ host_backups_item["retain_hourly"] }}
          {%- endif %}
          #
          {%- if "retain_daily" in backup %}
          retain_daily: {{ backup["retain_daily"] }}
          {%- elif "retain_daily" in host_backups_item %}
          retain_daily: {{ host_backups_item["retain_daily"] }}
          {%- endif %}
          #
          {%- if "retain_weekly" in backup %}
          retain_weekly: {{ backup["retain_weekly"] }}
          {%- elif "retain_weekly" in host_backups_item %}
          retain_weekly: {{ host_backups_item["retain_weekly"] }}
          {%- endif %}
          #
          {%- if "retain_monthly" in backup %}
          retain_monthly: {{ backup["retain_monthly"] }}
          {%- elif "retain_monthly" in host_backups_item %}
          retain_monthly: {{ host_backups_item["retain_monthly"] }}
          {%- endif %}
          #
          {%- if host_backups_item["rsync_args"] is defined %}
          rsync_args: {{ host_backups_item["rsync_args"] }}
          {%- endif %}
          {%- if host_backups_item["mysqldump_args"] is defined %}
          mysqldump_args: {{ host_backups_item["mysqldump_args"] }}
          {%- endif %}
          {%- if host_backups_item["mongo_args"] is defined %}
          mongo_args: {{ host_backups_item["mongo_args"] }}
          {%- endif %}
          {%- if host_backups_item["connect_user"] is defined %}
          connect_user: {{ host_backups_item["connect_user"] }}
          {%- endif %}
          {%- if host_backups_item["connect_password"] is defined %}
          connect_password: {{ host_backups_item["connect_password"] }}
          {%- endif %}
          # Per backup host item is higher priority than per backup item
          {%- if "before_backup_check" in backup %}
          before_backup_check: {{ backup["before_backup_check"] }}
          {%- elif "before_backup_check" in host_backups_item %}
          before_backup_check: {{ host_backups_item["before_backup_check"] }}
          {%- endif %}
          #
          {%- if host_backups_item["exec_before_rsync"] is defined %}
          exec_before_rsync: {{ host_backups_item["exec_before_rsync"] }}
          {%- endif %}
          {%- if host_backups_item["exec_after_rsync"] is defined %}
          exec_after_rsync: {{ host_backups_item["exec_after_rsync"] }}
          {%- endif %}
          {%- if host_backups_item["checks"] is defined %}
          checks:
            {%- for check in host_backups_item["checks"] %}
              {%- if check["data"] is defined %}
                {%- if check["data"] == source %}
            - type: {{ check["type"] }}
                  {%- if check["path"] is defined %}
              path: {{ check["path"] }}
                  {%- endif %}
                  {%- if check["min_file_size"] is defined %}
              min_file_size: {{ check["min_file_size"] }}
                  {%- endif %}
                  {%- if check["file_type"] is defined %}
              file_type: '{{ check["file_type"] }}'
                  {%- endif %}
                  {%- if check["last_file_age"] is defined %}
              last_file_age: {{ check["last_file_age"] }}
                  {%- endif %}
                  {%- if check["files_total"] is defined %}
              files_total: {{ check["files_total"] }}
                  {%- endif %}
                  {%- if check["files_mask"] is defined %}
              files_mask: '{{ check["files_mask"] }}'
                  {%- endif %}
                  {%- if check["s3_bucket"] is defined %}
              s3_bucket: '{{ check["s3_bucket"] }}'
                  {%- endif %}
                  {%- if check["s3_path"] is defined %}
              s3_path: '{{ check["s3_path"] }}'
                  {%- endif %}
                {%- endif %}
              {%- else %}
            - type: {{ check["type"] }}
                {%- if check["empty_db"] is defined %}
              empty_db: {{ check["empty_db"] }}
                {%- endif %}
                {%- if check["path"] is defined %}
              path: {{ check["path"] }}
                {%- endif %}
                {%- if check["min_file_size"] is defined %}
              min_file_size: {{ check["min_file_size"] }}
                {%- endif %}
                {%- if check["file_type"] is defined %}
              file_type: '{{ check["file_type"] }}'
                {%- endif %}
                {%- if check["last_file_age"] is defined %}
              last_file_age: {{ check["last_file_age"] }}
                {%- endif %}
                {%- if check["files_total"] is defined %}
              files_total: {{ check["files_total"] }}
                {%- endif %}
                {%- if check["files_mask"] is defined %}
              files_mask: '{{ check["files_mask"] }}'
                {%- endif %}
                {%- if check["s3_bucket"] is defined %}
              s3_bucket: '{{ check["s3_bucket"] }}'
                {%- endif %}
                {%- if check["s3_path"] is defined %}
              s3_path: '{{ check["s3_path"] }}'
                {%- endif %}
              {%- endif %}
            {%- endfor %}
          {%- endif %}
        {%- endfor %}
      {%- endif %}
    {%- endfor %}
  {%- endfor %}

{% else %}
rsnapshot_backup_dir:
  file.directory:
    - name: /opt/sysadmws/rsnapshot_backup
    - user: root
    - group: root
    - mode: 775
    - makedirs: True

  {%- if not salt["file.file_exists"]("/opt/sysadmws/rsnapshot_backup/rsnapshot_backup.conf") %}
# Just empty config if not exists - not to overwrite manually created config
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
{% endif %}
