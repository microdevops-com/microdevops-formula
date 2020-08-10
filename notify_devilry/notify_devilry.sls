{% if pillar["notify_devilry"] is defined %}
  {%- if "config_file_override" in pillar["notify_devilry"] %}

    {%- if salt["file.directory_exists"]("/opt/sysadmws/notify_devilry") %}
swsu_v1_notify_devilry_config_managed:
  file.managed:
    - name: "/opt/sysadmws/notify_devilry/notify_devilry.yaml"
    - mode: 0600
    - user: root
    - group: root
    - source: {{ pillar["notify_devilry"]["config_file_override"] }}
    {%- endif %}

  {%- elif "config_file" in pillar["notify_devilry"] %}

    {%- if salt["file.directory_exists"]("/opt/sysadmws/notify_devilry") %}
swsu_v1_notify_devilry_config_managed:
  file.managed:
    - name: "/opt/sysadmws/notify_devilry/notify_devilry.yaml"
    - mode: 0600
    - user: root
    - group: root
    - source: {{ pillar["notify_devilry"]["config_file"] }}
    {%- endif %}

  {%- endif %}

{% else %}
notify_devilry_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured for a minion of this type, so nothing has been done. But it is OK.

{% endif %}
