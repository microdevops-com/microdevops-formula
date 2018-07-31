{% if pillar['rsnapshot_backup'] is defined and pillar['rsnapshot_backup'] is not none %}

  # Check if data definition exists for this host (there may be other hosts in this pillar)
  {%- if pillar['rsnapshot_backup'][grains['fqdn']] is defined and pillar['rsnapshot_backup'][grains['fqdn']] is not none  %}

    # Get every data item
    {%- for data_item in pillar['rsnapshot_backup'][grains['fqdn']]['data'] %}
      {%- set i_loop = loop %}

      # Only if check defined at all
      {%- if data_item['checks'] is defined and data_item['checks'] is not none %}

        # Get every check inside with .backup_check check type
        {%- for check_item in data_item['checks'] %}
        {%- set j_loop = loop %}

          # Only .backup_check requires putting check files for now
          {%- if check_item['type'] == ".backup_check" %}

            # Loop over sources
            {%- for source in data_item['sources'] %}
            {%- set k_loop = loop %}

              # Expand special words in the source
              {%- if source == 'UBUNTU' %}
                {%- set source_items = ['/etc','/home','/root','/var/log','/var/spool/cron','/usr/local','/lib/ufw','/opt/sysadmws-utils'] -%}
              {%- elif source == 'DEBIAN' %}
                {%- set source_items = ['/etc','/home','/root','/var/log','/var/spool/cron','/usr/local','/lib/ufw','/opt/sysadmws-utils'] -%}
              {%- elif source == 'CENTOS' %}
                {%- set source_items = ['/etc','/home','/root','/var/log','/var/spool/cron','/usr/local'] -%}
              {%- else %}
                # Just one item - source itself
                {%- set source_items = [source] -%}
              {%- endif %}
              
              # Loop over expanded list of sources
              {%- for source_item in source_items %}
              {%- set l_loop = loop %}
            
put_check_files_{{ i_loop.index }}_{{ j_loop.index }}_{{ k_loop.index }}_{{ l_loop.index }}:
  file.managed:
    - name: '{{ source_item }}{{ '\\' if grains['os'] == "Windows" else '/' }}.backup_check'
    - contents:
      - 'Host: {{ grains['fqdn'] }}'
      - 'Path: {{ source_item }}'
      - 'UTC: {{ salt['cmd.shell']("powershell (get-date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')") if grains['os'] == "Windows" else salt['cmd.shell']('date -u "+%Y-%m-%d %H:%M:%S"') }}'
                {%- for backup_item in pillar['rsnapshot_backup'][grains['fqdn']]['backups'] %}
                {%- set m_loop = loop %}
      - 'Backup {{ m_loop.index }} Host: {{ backup_item['host'] }}'
      - 'Backup {{ m_loop.index }} Path: {{ backup_item['path'] }}'
                {%- endfor %}
              {%- endfor %}
            {%- endfor %}
          {%- endif %}
        {%- endfor %}
      {%- endif %}
    {%- endfor %}
  {%- endif %}
{% endif %}
