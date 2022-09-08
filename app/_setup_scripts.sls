      {%- if "setup_script_root" in app %}
        {%- set _app_cwd = app["setup_script_root"]["cwd"]|replace("__APP_NAME__", app_name) %}
app_{{ app_type }}_app_setup_script_root_run_{{ loop_index }}:
  cmd.run:
    - cwd: {{ _app_cwd }}
    - name: {{ app["setup_script_root"]["name"] | replace("__APP_NAME__", app_name) | yaml_encode }}
    - runas: root

      {%- endif %}

      {%- if "setup_script_app_user" in app %}
        {%- set _app_cwd = app["setup_script_app_user"]["cwd"]|replace("__APP_NAME__", app_name) %}
app_{{ app_type }}_app_setup_script_app_user_run_{{ loop_index }}:
  cmd.run:
    - cwd: {{ _app_cwd }}
    - name: {{ app["setup_script_app_user"]["name"] | replace("__APP_NAME__", app_name) | yaml_encode }}
    - runas: {{ _app_user }}

      {%- endif %}
