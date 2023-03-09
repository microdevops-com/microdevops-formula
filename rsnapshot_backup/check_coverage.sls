{% from "rsnapshot_backup/os_vars.jinja" import data_dirs_to_find with context %}
{% from "rsnapshot_backup/os_vars.jinja" import data_dirs_to_skip with context %}
{% from "rsnapshot_backup/os_vars.jinja" import data_expand with context %}
{% from "rsnapshot_backup/os_vars.jinja" import db_ps with context %}
{% if data_dirs_to_find[grains["oscodename"]] is defined and data_dirs_to_skip[grains["oscodename"]] is defined and db_ps[grains["oscodename"]] is defined %}

  {%- if pillar["rsnapshot_backup"] is defined and pillar["rsnapshot_backup"]["sources"][grains["id"]] is defined %}

    {# Data Dirs #}
    
    {# run all find dir commands and combine output in one list #}
    {%- set dir_list = [] %}
    {%- for find_item in data_dirs_to_find[grains["oscodename"]] %}
      {%- for find_result_item in salt["cmd.shell"](find_item).split() %}
        {%- do dir_list.append(find_result_item) %}
      {%- endfor %}
    {%- endfor %}

    {# check dirs for backups #}
    {%- for dir in dir_list %}
      {%- set data_dirs_backup_found = {dir: {"local": False, "remote": False}} %}
      {%- if dir not in data_dirs_to_skip[grains["oscodename"]] %}
        {# check if dir is not empty, . and .. are always present, so dir is not empty if > 2 #}
        {%- if salt["file.readdir"](dir)|length > 2 %}
          {# iterate over backup definition items #}
          {%- for backup_item in pillar["rsnapshot_backup"]["sources"][grains["id"]] %}
            {# iterate over backup data items of type RSYNC_SSH or SUPPRESS_COVERAGE #}
            {%- if backup_item["type"] == "SUPPRESS_COVERAGE" %}
              {%- for backup_data_item in backup_item["data"] %}
                {# expand macros #}
                {%- if backup_data_item in data_expand %}
                  {%- if dir in data_expand[backup_data_item] %}
                    {# check backup suppressions #}
                    {%- if backup_item["local_backups_suppress_reason"] is defined %}
                      {%- do data_dirs_backup_found[dir].update({"local": True}) %}
                    {%- endif %}
                    {%- if backup_item["remote_backups_suppress_reason"] is defined %}
                      {%- do data_dirs_backup_found[dir].update({"remote": True}) %}
                    {%- endif %}
                  {%- endif %}
                {%- elif dir == backup_data_item %}
                  {# check backup suppressions #}
                  {%- if backup_item["local_backups_suppress_reason"] is defined %}
                    {%- do data_dirs_backup_found[dir].update({"local": True}) %}
                  {%- endif %}
                  {%- if backup_item["remote_backups_suppress_reason"] is defined %}
                    {%- do data_dirs_backup_found[dir].update({"remote": True}) %}
                  {%- endif %}
                {%- endif %}
              {%- endfor %}
            {%- endif %}
            {%- if backup_item["type"] == "RSYNC_SSH" %}
              {%- for backup_data_item in backup_item["data"] %}
                {# expand macros #}
                {%- if backup_data_item in data_expand %}
                  {%- if dir in data_expand[backup_data_item] %}
                    {# iterate over backup backups items to find local and remote backups #}
                    {%- for backup_backups_item in backup_item["backups"] %}
                      {%- if backup_backups_item["host"] == grains["id"] %}
                        {%- do data_dirs_backup_found[dir].update({"local": True}) %}
                      {%- else %}
                        {%- do data_dirs_backup_found[dir].update({"remote": True}) %}
                      {%- endif %}
                    {%- endfor %}
                  {%- endif %}
                {%- elif dir == backup_data_item %}
                  {# iterate over backup backups items to find local and remote backups #}
                  {%- for backup_backups_item in backup_item["backups"] %}
                    {%- if backup_backups_item["host"] == grains["id"] %}
                      {%- do data_dirs_backup_found[dir].update({"local": True}) %}
                    {%- else %}
                      {%- do data_dirs_backup_found[dir].update({"remote": True}) %}
                    {%- endif %}
                  {%- endfor %}
                {%- endif %}
              {%- endfor %}
            {%- endif %}
          {%- endfor %}
          {# print results #}
          {%- if data_dirs_backup_found[dir]["local"] %}
check_coverage_local_backup_dir_found_{{ loop.index }}:
  test.configurable_test_state:
    - name: check local backup {{ dir }}
    - changes: False
    - result: True
    - comment: |
        NOTICE: local rsnapshot_backup of dir "{{ dir }}" found.
          {%- else %}
check_coverage_no_local_backup_dir_found_{{ loop.index }}:
  test.configurable_test_state:
    - name: check local backup {{ dir }}
    - changes: False
    - result: False
    - comment: |
        ERROR: local rsnapshot_backup of dir "{{ dir }}" not found.
          {%- endif %}
          {%- if data_dirs_backup_found[dir]["remote"] %}
check_coverage_remote_backup_dir_found_{{ loop.index }}:
  test.configurable_test_state:
    - name: check remote backup {{ dir }}
    - changes: False
    - result: True
    - comment: |
        NOTICE: remote rsnapshot_backup of dir "{{ dir }}" found.
          {%- else %}
check_coverage_no_remote_backup_dir_found_{{ loop.index }}:
  test.configurable_test_state:
    - name: check remote backup {{ dir }}
    - changes: False
    - result: False
    - comment: |
        ERROR: remote rsnapshot_backup of dir "{{ dir }}" not found.
          {%- endif %}
        {%- endif %}
      {%- endif %}
    {%- endfor %}
    
    {# Databases #}

    {%- for db, ps in db_ps[grains["oscodename"]].items() %}
      {# check if process running, but not in container #}
      {%- set cmd = 'ps -e -o pid -o cgroup -o command | grep -v -e ":/lxc" -e "grep" | grep -q "' + ps + '"' %}
      {%- if salt["cmd.retcode"](cmd, python_shell=True) == 0 %}
        {%- set db_backup_found = {db: {"local": False, "remote": False}} %}
        {# iterate over backup definition items #}
        {%- for backup_item in pillar["rsnapshot_backup"]["sources"][grains["id"]] %}
          {# iterate over backup data items of type {{ db }}_SSH or SUPPRESS_COVERAGE #}
          {%- if backup_item["type"] == "SUPPRESS_COVERAGE" %}
            {%- for backup_data_item in backup_item["data"] %}
              {%- if backup_data_item == db and backup_item["local_backups_suppress_reason"] is defined %}
                {%- do db_backup_found[db].update({"local": True}) %}
              {%- endif %}
              {%- if backup_data_item == db and backup_item["remote_backups_suppress_reason"] is defined %}
                {%- do db_backup_found[db].update({"remote": True}) %}
              {%- endif %}
            {%- endfor %}
          {%- endif %}
          {%- if backup_item["type"] == db + "_SSH" %}
            {# iterate over backup backups items to find local and remote backups #}
            {%- for backup_backups_item in backup_item["backups"] %}
              {%- if backup_backups_item["host"] == grains["id"] %}
                {%- do db_backup_found[db].update({"local": True}) %}
              {%- else %}
                {%- do db_backup_found[db].update({"remote": True}) %}
              {%- endif %}
            {%- endfor %}
          {%- endif %}
        {%- endfor %}
        {# print results #}
        {%- if db_backup_found[db]["local"] %}
check_coverage_local_backup_{{ db }}_found:
  test.configurable_test_state:
    - name: check local backup {{ db }}
    - changes: False
    - result: True
    - comment: |
        NOTICE: local rsnapshot_backup of {{ db }} found.
        {%- else %}
check_coverage_no_local_backup_{{ db }}_found:
  test.configurable_test_state:
    - name: check local backup {{ db }}
    - changes: False
    - result: False
    - comment: |
        ERROR: local rsnapshot_backup of {{ db }} not found.
        {%- endif %}
        {%- if db_backup_found[db]["remote"] %}
check_coverage_remote_backup_{{ db }}_found:
  test.configurable_test_state:
    - name: check remote backup {{ db }}
    - changes: False
    - result: True
    - comment: |
        NOTICE: remote rsnapshot_backup of {{ db }} found.
        {%- else %}
check_coverage_no_remote_backup_{{ db }}_found:
  test.configurable_test_state:
    - name: check remote backup {{ db }}
    - changes: False
    - result: False
    - comment: |
        ERROR: remote rsnapshot_backup of {{ db }} not found.
        {%- endif %}
      {%- endif %}
    {%- endfor %}
    
  {%- else %}
check_coverage_no_server_in_sources:
  test.configurable_test_state:
    - name: no server in sources
    - changes: False
    - result: False
    - comment: |
        ERROR: "{{ grains["id"] }}" not found in pillar:rsnapshot_backup:sources list - rsnapshot_backup is not configured at all.
  {%- endif %}
  
{% elif grains["os"] == "Windows" %}
check_coverage_nothing_to_do:
  test.configurable_test_state:
    - name: check_coverage_nothing_to_do_info
    - changes: False
    - result: True
    - comment: |
         NOTICE: check_coverage is not for Windows, doing nothing.

{% else %}
check_coverage_unknown_oscodename:
  test.configurable_test_state:
    - name: unknown oscodename
    - changes: False
    - result: False
    - comment: |
        ERROR: "{{ grains["oscodename"] }}" not found in os_vars.jinja vars data_dirs_to_find, data_dirs_to_skip. Cannot get standard dirs without it.
{% endif %}
