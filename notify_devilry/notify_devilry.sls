{% if pillar["notify_devilry"] is defined %}
notify_devilry_dir:
  file.directory:
    - name: /opt/sysadmws/notify_devilry
    - user: root
    - group: root
    - mode: 0775

  {%- if "config_file_override" in pillar["notify_devilry"] %}
notify_devilry_config_managed:
  file.managed:
    - name: /opt/sysadmws/notify_devilry/notify_devilry.yaml
    - mode: 0600
    - user: root
    - group: root
    - source: {{ pillar["notify_devilry"]["config_file_override"] }}
    {%- if "defaults" in pillar["notify_devilry"] %}
    - template: jinja
    - defaults:
      {%- for def_key, def_val in pillar["notify_devilry"]["defaults"].items() %}
        {{ def_key }}: {{ def_val }}
      {%- endfor %}
    {%- endif %}

  {%- elif "config_file" in pillar["notify_devilry"] %}
notify_devilry_config_managed:
  file.managed:
    - name: /opt/sysadmws/notify_devilry/notify_devilry.yaml
    - mode: 0600
    - user: root
    - group: root
    - source: {{ pillar["notify_devilry"]["config_file"] }}
    {%- if "defaults" in pillar["notify_devilry"] %}
    - template: jinja
    - defaults:
      {%- for def_key, def_val in pillar["notify_devilry"]["defaults"].items() %}
        {{ def_key }}: {{ def_val }}
      {%- endfor %}
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
