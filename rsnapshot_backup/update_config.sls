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
            {%- if "priority" in backup %}
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

# rsnapshot_backup.conf is for legacy sh+awk version of rsnapshot_backup
# Not all features that come to yaml+py version must come here
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
          connect: {{ backup["connect"] if "connect" in backup else host_backups_item["_host"] }}
          host: {{ host_backups_item["_host"] }}
          type: {{ host_backups_item["type"] }}
          source: {{ source }}
          path: {{ backup["path"] }}
          validate_hostname: {{ host_backups_item["validate_hostname"]|default(True) }}
          postgresql_noclean: {{ host_backups_item["postgresql_noclean"]|default(False) }}
          mysql_noevents: {{ host_backups_item["mysql_noevents"]|default(False) }}
          native_txt_check: {{ host_backups_item["native_txt_check"]|default(False) }}
          native_10h_limit: {{ host_backups_item["native_10h_limit"]|default(False) }}
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
          {%- if "rsync_args" in host_backups_item %}
          rsync_args: {{ host_backups_item["rsync_args"] }}
          {%- endif %}
          #
          {%- if "mysqldump_args" in host_backups_item %}
          mysqldump_args: {{ host_backups_item["mysqldump_args"] }}
          {%- endif %}
          #
          {%- if "mongo_args" in host_backups_item %}
          mongo_args: {{ host_backups_item["mongo_args"] }}
          {%- endif %}
          #
          {%- if "mongodump_args" in host_backups_item %}
          mongodump_args: {{ host_backups_item["mongodump_args"] }}
          {%- endif %}
          #
          {%- if "connect_user" in host_backups_item %}
          connect_user: {{ host_backups_item["connect_user"] }}
          {%- endif %}
          #
          {%- if "connect_password" in host_backups_item %}
          connect_password: {{ host_backups_item["connect_password"] }}
          {%- endif %}
          # Per backup host item is higher priority than per backup item
          {%- if "before_backup_check" in backup %}
          before_backup_check: {{ backup["before_backup_check"] }}
          {%- elif "before_backup_check" in host_backups_item %}
          before_backup_check: {{ host_backups_item["before_backup_check"] }}
          {%- endif %}
          #
          {%- if "exec_before_rsync" in host_backups_item %}
          exec_before_rsync: {{ host_backups_item["exec_before_rsync"] }}
          {%- endif %}
          #
          {%- if "exec_after_rsync" in host_backups_item %}
          exec_after_rsync: {{ host_backups_item["exec_after_rsync"] }}
          {%- endif %}
          #
          {%- if "exclude" in host_backups_item %}
          exclude: {{ host_backups_item["exclude"] }}
          {%- endif %}
          #
          {%- if "checks" in host_backups_item %}
            # Some checks have data param to set params for specific data item, so add checks only if matched data item (source var)
            {%- for check in host_backups_item["checks"] if "data" not in check or check["data"] == source %}
              # Add check only once, moved inside loop not to add "checks: null" if no checks
              {%- if loop.index == 1 %}
          checks:
              {%- endif %}
              #
            - type: {{ check["type"] }}
              {%- if "path" in check %}
              path: {{ check["path"] }}
              {%- endif %}
              #
              {%- if "empty_db" in check %}
              empty_db: {{ check["empty_db"] }}
              {%- endif %}
              #
              {%- if "min_file_size" in check %}
              min_file_size: {{ check["min_file_size"] }}
              {%- endif %}
              #
              {%- if "file_type" in check %}
              file_type: '{{ check["file_type"] }}'
              {%- endif %}
              #
              {%- if "last_file_age" in check %}
              last_file_age: {{ check["last_file_age"] }}
              {%- endif %}
              #
              {%- if "files_total" in check %}
              files_total: {{ check["files_total"] }}
              {%- endif %}
              #
              {%- if "files_mask" in check %}
              files_mask: '{{ check["files_mask"] }}'
              {%- endif %}
              #
              {%- if "s3_bucket" in check %}
              #
              s3_bucket: '{{ check["s3_bucket"] }}'
              {%- endif %}
              #
              {%- if "s3_path" in check %}
              s3_path: '{{ check["s3_path"] }}'
              {%- endif %}
              #
            {%- endfor %}
          {%- endif %}
        {%- endfor %}
      {%- endif %}
    {%- endfor %}
  {%- endfor %}

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
        enabled: True
        comment: This file is managed by Salt, local changes will be overwritten.
        items:
        - enabled: False # The first item in the dataset list is always empty, just to have at least somthing in the list, if no backups found (empty dataset produces errors)
          number: -1
          comment: Just to have at least somthing in the list, if no backups found
  {%- set global_vars = {"number": 0} %}
  {%- for host_backups_item in host_backups_items|sort(attribute="_priority") %}
    {%- for backup in host_backups_item["backups"] %}
      {%- if grains["id"] == backup["host"] %}
        {%- for source in host_backups_item["data"] %}
        - enabled: True
          number: {{ global_vars["number"] }}
          {%- do global_vars.update({"number": global_vars["number"] + 1}) %}
          connect: {{ backup["connect"] if "connect" in backup else host_backups_item["_host"] }}
          host: {{ host_backups_item["_host"] }}
          type: {{ host_backups_item["type"] }}
          source: {{ source }}
          path: {{ backup["path"] }}
          #
          {%- if "validate_hostname" in host_backups_item %}
          validate_hostname: {{ host_backups_item["validate_hostname"] }}
          {%- endif %}
          #
          {%- if "postgresql_noclean" in host_backups_item %}
          postgresql_noclean: {{ host_backups_item["postgresql_noclean"] }}
          {%- endif %}
          #
          {%- if "mysql_noevents" in host_backups_item %}
          mysql_noevents: {{ host_backups_item["mysql_noevents"] }}
          {%- endif %}
          #
          {%- if "native_txt_check" in host_backups_item %}
          native_txt_check: {{ host_backups_item["native_txt_check"] }}
          {%- endif %}
          #
          {%- if "native_10h_limit" in host_backups_item %}
          native_10h_limit: {{ host_backups_item["native_10h_limit"] }}
          {%- endif %}
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
          {%- if "rsync_args" in host_backups_item %}
          rsync_args: {{ host_backups_item["rsync_args"] }}
          {%- endif %}
          #
          {%- if "mysqldump_args" in host_backups_item %}
          mysqldump_args: {{ host_backups_item["mysqldump_args"] }}
          {%- endif %}
          # only for py
          {%- if "pg_dump_args" in host_backups_item %}
          pg_dump_args: {{ host_backups_item["pg_dump_args"] }}
          {%- endif %}
          #
          {%- if "mongo_args" in host_backups_item %}
          mongo_args: {{ host_backups_item["mongo_args"] }}
          {%- endif %}
          #
          {%- if "mongodump_args" in host_backups_item %}
          mongodump_args: {{ host_backups_item["mongodump_args"] }}
          {%- endif %}
          #
          {%- if "connect_user" in host_backups_item %}
          connect_user: {{ host_backups_item["connect_user"] }}
          {%- endif %}
          #
          {%- if "connect_password" in host_backups_item %}
          connect_password: {{ host_backups_item["connect_password"] }}
          {%- endif %}
          # Per backup host item is higher priority than per backup item
          {%- if "before_backup_check" in backup %}
          before_backup_check: {{ backup["before_backup_check"] }}
          {%- elif "before_backup_check" in host_backups_item %}
          before_backup_check: {{ host_backups_item["before_backup_check"] }}
          {%- endif %}
          #
          {%- if "exec_before_rsync" in host_backups_item %}
          exec_before_rsync: {{ host_backups_item["exec_before_rsync"] }}
          {%- endif %}
          #
          {%- if "exec_after_rsync" in host_backups_item %}
          exec_after_rsync: {{ host_backups_item["exec_after_rsync"] }}
          {%- endif %}
          #
          {%- if "exclude" in host_backups_item %}
          exclude: {{ host_backups_item["exclude"] }}
          {%- endif %}
          # only for py everything below
          {%- if "dump_prefix_cmd" in host_backups_item %}
          dump_prefix_cmd: {{ host_backups_item["dump_prefix_cmd"] }}
          {%- endif %}
          #
          {%- if "mysql_dump_dir" in host_backups_item %}
          mysql_dump_dir: {{ host_backups_item["mysql_dump_dir"] }}
          {%- endif %}
          #
          {%- if "postgresql_dump_dir" in host_backups_item %}
          postgresql_dump_dir: {{ host_backups_item["postgresql_dump_dir"] }}
          {%- endif %}
          #
          {%- if "mongodb_dump_dir" in host_backups_item %}
          mongodb_dump_dir: {{ host_backups_item["mongodb_dump_dir"] }}
          {%- endif %}
          #
          {%- if "mysql_dump_type" in host_backups_item %}
          mysql_dump_type: {{ host_backups_item["mysql_dump_type"] }}
          {%- endif %}
          #
          {%- if "xtrabackup_throttle" in host_backups_item %}
          xtrabackup_throttle: {{ host_backups_item["xtrabackup_throttle"] }}
          {%- endif %}
          #
          {%- if "xtrabackup_parallel" in host_backups_item %}
          xtrabackup_parallel: {{ host_backups_item["xtrabackup_parallel"] }}
          {%- endif %}
          #
          {%- if "xtrabackup_compress_threads" in host_backups_item %}
          xtrabackup_compress_threads: {{ host_backups_item["xtrabackup_compress_threads"] }}
          {%- endif %}
          #
          {%- if "xtrabackup_args" in host_backups_item %}
          xtrabackup_args: {{ host_backups_item["xtrabackup_args"] }}
          {%- endif %}
          #
          {%- if "mysqlsh_connect_args" in host_backups_item %}
          mysqlsh_connect_args: {{ host_backups_item["mysqlsh_connect_args"] }}
          {%- endif %}
          #
          {%- if "mysqlsh_args" in host_backups_item %}
          mysqlsh_args: {{ host_backups_item["mysqlsh_args"] }}
          {%- endif %}
          #
          {%- if "mysqlsh_max_rate" in host_backups_item %}
          mysqlsh_max_rate: {{ host_backups_item["mysqlsh_max_rate"] }}
          {%- endif %}
          #
          {%- if "mysqlsh_bytes_per_chunk" in host_backups_item %}
          mysqlsh_bytes_per_chunk: {{ host_backups_item["mysqlsh_bytes_per_chunk"] }}
          {%- endif %}
          #
          {%- if "mysqlsh_threads" in host_backups_item %}
          mysqlsh_threads: {{ host_backups_item["mysqlsh_threads"] }}
          {%- endif %}
          #
          {%- if "retries" in host_backups_item %}
          retries: {{ host_backups_item["retries"] }}
          {%- endif %}
          # Per backup host item is higher priority than per backup item
          {%- if "rsnapshot_prefix_cmd" in backup %}
          rsnapshot_prefix_cmd: {{ backup["rsnapshot_prefix_cmd"] }}
          {%- elif "rsnapshot_prefix_cmd" in host_backups_item %}
          rsnapshot_prefix_cmd: {{ host_backups_item["rsnapshot_prefix_cmd"] }}
          {%- endif %}
          #
          {%- if "checks" in host_backups_item %}
            # Some checks have data param to set params for specific data item, so add checks only if matched data item (source var)
            {%- for check in host_backups_item["checks"] if "data" not in check or check["data"] == source %}
              # Add check only once, moved inside loop not to add "checks: null" if no checks
              {%- if loop.index == 1 %}
          checks:
              {%- endif %}
              #
            - type: {{ check["type"] }}
              {%- if "path" in check %}
              path: {{ check["path"] }}
              {%- endif %}
              #
              {%- if "empty_db" in check %}
              empty_db: {{ check["empty_db"] }}
              {%- endif %}
              #
              {%- if "min_file_size" in check %}
              min_file_size: {{ check["min_file_size"] }}
              {%- endif %}
              #
              {%- if "file_type" in check %}
              file_type: '{{ check["file_type"] }}'
              {%- endif %}
              #
              {%- if "last_file_age" in check %}
              last_file_age: {{ check["last_file_age"] }}
              {%- endif %}
              #
              {%- if "files_total" in check %}
              files_total: {{ check["files_total"] }}
              {%- endif %}
              #
              {%- if "files_total_max" in check %}
              files_total_max: {{ check["files_total_max"] }}
              {%- endif %}
              #
              {%- if "files_mask" in check %}
              files_mask: '{{ check["files_mask"] }}'
              {%- endif %}
              #
              {%- if "s3_bucket" in check %}
              #
              s3_bucket: '{{ check["s3_bucket"] }}'
              {%- endif %}
              #
              {%- if "s3_path" in check %}
              s3_path: '{{ check["s3_path"] }}'
              {%- endif %}
              #
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
        enabled: False
        comment: This file is managed by Salt, local changes will be overwritten.
        items:
        - enabled: False

  {%- endif %}

{% endif %}
