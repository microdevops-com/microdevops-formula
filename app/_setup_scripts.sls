      {%- if "setup_script_root" in app %}
app_{{ app_type }}_app_setup_script_root_run_{{ loop.index }}:
  cmd.run:
    - cwd: {{ app["setup_script_root"]["cwd"] }}
    - name: {{ app["setup_script_root"]["name"] | yaml_encode }}
    - runas: root

      {%- endif %}

      {%- if "setup_script_app_user" in app %}
app_{{ app_type }}_app_setup_script_app_user_run_{{ loop.index }}:
  cmd.run:
    - cwd: {{ app["setup_script_app_user"]["cwd"] }}
    - name: {{ app["setup_script_app_user"]["name"] | yaml_encode }}
    - runas: {{ app["user"] }}

      {%- endif %}
