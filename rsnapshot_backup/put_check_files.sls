{% if pillar['rsnapshot_backup'] is defined and pillar['rsnapshot_backup'] is not none and pillar['rsnapshot_backup']['sources'] is defined and pillar['rsnapshot_backup']['sources'] is not none %}

  # Check if data definition exists for this host (there may be other hosts in this pillar)
  {%- if pillar['rsnapshot_backup']['sources'][grains['fqdn']] is defined and pillar['rsnapshot_backup']['sources'][grains['fqdn']] is not none  %}

    # Get every data item
    {%- for source_item in pillar['rsnapshot_backup']['sources'][grains['fqdn']] %}
      {%- set i_loop = loop %}

      # Only if check defined at all
      {%- if source_item['checks'] is defined and source_item['checks'] is not none %}

        # Get every check inside with .backup check type
        {%- for check_item in source_item['checks'] %}
        {%- set j_loop = loop %}

          # Simulate loop control with check_condition var
          {%- set check_condition = True %}

          # Check put_at_utc_hour
          {%- if check_item['put_at_utc_hour'] is defined and check_item['put_at_utc_hour'] is not none %}
            {%- set current_utc_hour = salt['cmd.shell']("powershell (get-date).ToUniversalTime().ToString('HH')") if grains['os'] == "Windows" else salt['cmd.shell']('date -u "+%H"') %}
            {%- if current_utc_hour|string != check_item['put_at_utc_hour']|string %}
              {%- set check_condition = False %}
            {%- endif %}
          {%- endif %}

          # Check condition
          {%- if check_condition %}

            # Type .backup
            {%- if check_item['type'] == ".backup" %}

              # Loop over sources
              {%- for data_item in source_item['data'] %}
              {%- set k_loop = loop %}

                # Expand special words in the data_item
                {%- if data_item == 'UBUNTU' %}
                  {%- set expanded_data = ['/etc','/home','/root','/var/log','/var/spool/cron','/usr/local','/lib/ufw','/opt/sysadmws'] -%}
                {%- elif data_item == 'DEBIAN' %}
                  {%- set expanded_data = ['/etc','/home','/root','/var/log','/var/spool/cron','/usr/local','/lib/ufw','/opt/sysadmws'] -%}
                {%- elif data_item == 'CENTOS' %}
                  {%- set expanded_data = ['/etc','/home','/root','/var/log','/var/spool/cron','/usr/local'] -%}
                # Just one item data_item itself
                {%- else %}
                  # Check if check has path subst by data
                  {%- if check_item['data'] is defined and check_item['data'] is not none and check_item['data'] == data_item %}
                    {%- set expanded_data = [check_item['path']] -%}
                  {%- else %}
                    {%- set expanded_data = [data_item] -%}
                  {%- endif %}
                {%- endif %}

                # Loop over expanded list
                {%- for expanded_data_item in expanded_data %}
                {%- set l_loop = loop %}

put_check_files_{{ i_loop.index }}_{{ j_loop.index }}_{{ k_loop.index }}_{{ l_loop.index }}:
  file.managed:
    - name: '{{ expanded_data_item }}{{ '\\' if grains['os'] == "Windows" else '/' }}.backup'
    - contents:
      - 'Host: {{ grains['fqdn'] }}'
      - 'Path: {{ expanded_data_item }}'
      - 'UTC: {{ salt['cmd.shell']("powershell (get-date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')") if grains['os'] == "Windows" else salt['cmd.shell']('date -u "+%Y-%m-%d %H:%M:%S"') }}'
                  {%- for backup_item in source_item['backups'] %}
                  {%- set m_loop = loop %}
      - 'Backup {{ m_loop.index }} Host: {{ backup_item['host'] }}'
      - 'Backup {{ m_loop.index }} Path: {{ backup_item['path'] }}'
                  {%- endfor %}

                {%- endfor %}
              {%- endfor %}
            {%- endif %}

            # Type s3/.backup
            # The idea is to put .backup to bucket, which somehow is synced to backup then.
            # Loop over data - no need to be done, because .backup file path is defined by s3_ keys of the check.
            # Even if you define several data and this check type, file would be overwritten by the last one.
            {%- if check_item['type'] == "s3/.backup" %}

put_check_files_tmp_{{ i_loop.index }}_{{ j_loop.index }}:
  file.managed:
    - name: '/tmp/put_check_files/.backup'
    - makedirs: True
    - contents:
      - 'Bucket: {{ check_item['s3_bucket'] }}'
      - 'Path: {{ check_item['s3_path'] }}'
      - 'UTC: {{ salt['cmd.shell']('date -u "+%Y-%m-%d %H:%M:%S"') }}'
              {%- for backup_item in source_item['backups'] %}
              {%- set m_loop = loop %}
      - 'Backup {{ m_loop.index }} Host: {{ backup_item['host'] }}'
      - 'Backup {{ m_loop.index }} Path: {{ backup_item['path'] }}'
              {%- endfor %}

put_check_files_tmp_upload_{{ i_loop.index }}_{{ j_loop.index }}:
  module.run:
    - name: s3.put
    - bucket: '{{ check_item['s3_bucket'] }}'
    - path: '{{ check_item['s3_path'] }}/.backup'
    - local_file: '/tmp/put_check_files/.backup'
    - keyid: '{{ check_item['s3_keyid'] }}'
    - key: '{{ check_item['s3_key'] }}'

            {%- endif %}

          {%- endif %}

        {%- endfor %}
      {%- endif %}
    {%- endfor %}
  {%- endif %}
{% endif %}
