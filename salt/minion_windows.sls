{% if pillar["salt"] is defined and "minion" in pillar["salt"] and grains["os"] in ["Windows"] %}

  {%- if pillar["salt"]["minion"]["version"]|string == "3001" %}
    {%- set minion_src = 'https://archive.repo.saltproject.io/windows/Salt-Minion-' ~ pillar["salt"]["minion"]["version"]|string ~ '-Py3-AMD64-Setup.exe' -%}
  # This block should be updated each time new minor version comes
  {%- elif pillar["salt"]["minion"]["version"]|string == "3004" %}
    {%- set minion_src = 'https://repo.saltstack.com/windows/Salt-Minion-' ~ pillar["salt"]["minion"]["version"]|string ~ '.1-Py3-AMD64-Setup.exe' -%}
  {%- else %}
    {%- set minion_src = 'https://repo.saltstack.com/windows/Salt-Minion-' ~ pillar["salt"]["minion"]["version"]|string ~ '.1-Py3-AMD64-Setup.exe' -%}
  {%- endif %}
  {%- set minion_exe = 'Salt-Minion-' ~ pillar["salt"]["minion"]["version"]|string ~ '-Py3-AMD64-Setup.exe' -%}

  {%- if 
         pillar["salt"]["minion"]["version"]|string != grains["saltversioninfo"][0]|string
         or
         (pillar["salt"]["minion"]["release"] is defined and pillar["salt"]["minion"]["release"] != grains["saltversioninfo"][0]|string + "." + grains["saltversioninfo"][1]|string)
  %}
minion_installer_exe:
  file.managed:
    - name: 'C:\Windows\{{ minion_exe }}' # DO NOT USE "" here - slash \ is treated as escape inside
    - source: '{{ minion_src }}'
    - source_hash: '{{ minion_src }}.sha256'

minion_install_silent_cmd:
  cmd.run:
    - name: |
        START /B C:\Windows\{{ minion_exe }} /S /master={{ pillar["salt"]["minion"]["config"]["master"]|join(",") }} /minion-name={{ grains["id"] }} /start-minion=1
  {%- endif %}

  {%- if pillar["salt"]["minion"]["grains_file_rm"] is defined and pillar["salt"]["minion"]["grains_file_rm"] %}
salt_minion_grains_file_rm:
  file.absent:
    - name: 'C:\salt\conf\grains'
  {%- endif %}

salt_minion_id:
  file.managed:
    - name: 'C:\salt\conf\minion_id'
    - contents: |
        {{ grains["id"] }}

salt_minion_config:
  file.serialize:
    - name: 'C:\salt\conf\minion'
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: yaml
    - dataset: {{ pillar["salt"]["minion"]["config"] }}

salt_minion_config_restart:
  module.run:
    - name: service.restart
    - m_name: salt-minion
    - onchanges:
        - file: 'C:\salt\conf\minion'
        - file: 'C:\salt\conf\grains'
        - file: 'C:\salt\conf\minion_id'

{% else %}
salt_minion_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured or wrong OS, so nothing has been done. But it is OK.

{% endif %}
