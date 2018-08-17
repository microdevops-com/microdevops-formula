{% if pillar['notify_devilry'] is defined and pillar['notify_devilry'] is not none and pillar['notify_devilry']['config_file'] is defined and pillar['notify_devilry']['config_file'] is not none %}

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

{% endif %}
