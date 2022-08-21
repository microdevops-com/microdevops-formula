{% from "rsnapshot_backup/os_vars.jinja" import data_expand with context %}

put_check_files_nothing_to_do:
  test.configurable_test_state:
    - name: put_check_files_pretend_doing_something
    - changes: False
    - result: True
    - comment: |
         NOTICE: Pretend doing something in case pillar results no actions further.

{% if pillar["rsnapshot_backup"] is defined and "sources" in pillar["rsnapshot_backup"] %}

  # Check if data definition exists for this host (there may be other hosts in this pillar)
  {%- if pillar["rsnapshot_backup"]["sources"][grains["id"]] is defined %}

    # Get every data item
    {%- for source_item in pillar["rsnapshot_backup"]["sources"][grains["id"]] %}
      {%- set i_loop = loop %}

      # Only if check defined at all
      {%- if source_item["checks"] is defined %}

        # Get every check inside with .backup check type
        {%- for check_item in source_item["checks"] %}
        {%- set j_loop = loop %}

          # Type .backup
          {%- if check_item["type"] == ".backup" %}

            # Loop over sources
            {%- for data_item in source_item["data"] %}
            {%- set k_loop = loop %}

              # Expand special words in the data_item
              {%- if data_item in data_expand %}
                {%- set expanded_data = data_expand[data_item] -%}
              # Just one item data_item itself
              {%- else %}
                # Check if check has path subst by data
                {%- if check_item["data"] is defined %}
                  # If subst only matched check
                  {%- if check_item["data"] == data_item %}
                    {%- set expanded_data = [check_item["path"]] -%}
                  {%- else %}
                    {%- set expanded_data = none -%}
                  {%- endif %}
                # No subst, just data_item itself
                {%- else %}
                  {%- set expanded_data = [data_item] -%}
                {%- endif %}
              {%- endif %}

              # Loop over expanded list if expanded_data is not none
              {%- if expanded_data is not none %}
                # Skip items if in exclude
                {%- for expanded_data_item in expanded_data if "exclude" not in source_item or expanded_data_item not in source_item["exclude"]  %}
                {%- set l_loop = loop %}

put_check_files_{{ i_loop.index }}_{{ j_loop.index }}_{{ k_loop.index }}_{{ l_loop.index }}:
  file.managed:
    - name: '{{ expanded_data_item }}{{ '\\' if grains["os"] == "Windows" else '/' }}.backup'
    - contents:
      - 'Host: {{ grains["id"] }}'
      - 'Path: {{ expanded_data_item }}'
      - 'UTC: {{ salt["cmd.shell"]("powershell (get-date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')") if grains["os"] == "Windows" else salt["cmd.shell"]('date -u "+%Y-%m-%d %H:%M:%S"') }}'
                  {%- for backup_item in source_item["backups"] %}
                  {%- set m_loop = loop %}
      - 'Backup {{ m_loop.index }} Host: {{ backup_item["host"] }}'
      - 'Backup {{ m_loop.index }} Path: {{ backup_item["path"] }}'
                  {%- endfor %}

                {%- endfor %}
              {%- endif %}
            {%- endfor %}
          {%- endif %}

          # Type s3/.backup
          # The idea is to put .backup to bucket, which somehow is synced to backup then.
          # Loop over data - no need to be done, because .backup file path is defined by s3_ keys of the check.
          # Even if you define several data and this check type, file would be overwritten by the last one.
          {%- if check_item["type"] == "s3/.backup" %}

put_check_files_tmp_{{ i_loop.index }}_{{ j_loop.index }}:
  file.managed:
    - name: '/tmp/put_check_files/.backup'
    - makedirs: True
    - contents:
      - 'Bucket: {{ check_item["s3_bucket"] }}'
      - 'Path: {{ check_item["s3_path"] }}'
      - 'UTC: {{ salt["cmd.shell"]('date -u "+%Y-%m-%d %H:%M:%S"') }}'
            {%- for backup_item in source_item["backups"] %}
            {%- set m_loop = loop %}
      - 'Backup {{ m_loop.index }} Host: {{ backup_item["host"] }}'
      - 'Backup {{ m_loop.index }} Path: {{ backup_item["path"] }}'
            {%- endfor %}

put_check_files_tmp_upload_{{ i_loop.index }}_{{ j_loop.index }}:
  cmd.run:
    - env:
      - AWS_ACCESS_KEY_ID: '{{ check_item["s3_keyid"] }}'
      - AWS_SECRET_ACCESS_KEY: '{{ check_item["s3_key"] }}'
    - name: aws s3 cp '/tmp/put_check_files/.backup' 's3://{{ check_item["s3_bucket"] }}/{{ check_item["s3_path"] }}/.backup'

          {%- endif %}

        {%- endfor %}
      {%- endif %}
    {%- endfor %}
  {%- endif %}
{% endif %}
