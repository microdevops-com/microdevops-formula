  {%- if "pre_deploy_cmd" in pillar["app"] %}
  # For app.mini, app.deploy this will be duplicated for each defined app type

app_{{ app_type }}_pre_deploy_cmd:
  cmd.run:
    - cwd: {{ pillar["app"]["pre_deploy_cmd"]["cwd"] }}
    - name: {{ pillar["app"]["pre_deploy_cmd"]["name"] | yaml_encode }}
    - runas: root

  {%- endif %}
