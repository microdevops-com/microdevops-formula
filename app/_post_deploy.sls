  {%- if "post_deploy_cmd" in pillar["app"] %}
  # For app.mini, app.deploy this will be duplicated for each defined app type

app_{{ app_type }}_post_deploy_cmd:
  cmd.run:
    - cwd: {{ pillar["app"]["post_deploy_cmd"]["cwd"] }}
    - name: {{ pillar["app"]["post_deploy_cmd"]["name"] | yaml_encode }}
    - runas: root

  {%- endif %}
