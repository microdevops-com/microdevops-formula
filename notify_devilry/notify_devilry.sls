{% if pillar['notify_devilry'] is defined and pillar['notify_devilry'] is not none and pillar['notify_devilry']['enabled'] is defined and pillar['notify_devilry']['enabled'] is not none %}
  {%- if pillar['notify_devilry']['config_file_override'] is defined and pillar['notify_devilry']['config_file_override'] is not none %}

    {%- if salt['file.directory_exists']('/opt/sysadmws-utils/notify_devilry') %}
swsu_v0_notify_devilry_config_managed:
  file.managed:
    - name: '/opt/sysadmws-utils/notify_devilry/notify_devilry.yaml.jinja'
    - mode: 0600
    - user: root
    - group: root
    - source: {{ pillar['notify_devilry']['config_file_override'] }}
    {%- endif %}

    {%- if salt['file.directory_exists']('/opt/sysadmws/notify_devilry') %}
swsu_v1_notify_devilry_config_managed:
  file.managed:
    - name: '/opt/sysadmws/notify_devilry/notify_devilry.yaml.jinja'
    - mode: 0600
    - user: root
    - group: root
    - source: {{ pillar['notify_devilry']['config_file_override'] }}
    {%- endif %}

  {%- elif pillar['notify_devilry']['config_file'] is defined and pillar['notify_devilry']['config_file'] is not none %}

    {%- if salt['file.directory_exists']('/opt/sysadmws-utils/notify_devilry') %}
swsu_v0_notify_devilry_config_managed:
  file.managed:
    - name: '/opt/sysadmws-utils/notify_devilry/notify_devilry.yaml.jinja'
    - mode: 0600
    - user: root
    - group: root
    - source: {{ pillar['notify_devilry']['config_file'] }}
    {%- endif %}

    {%- if salt['file.directory_exists']('/opt/sysadmws/notify_devilry') %}
swsu_v1_notify_devilry_config_managed:
  file.managed:
    - name: '/opt/sysadmws/notify_devilry/notify_devilry.yaml.jinja'
    - mode: 0600
    - user: root
    - group: root
    - source: {{ pillar['notify_devilry']['config_file'] }}
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
