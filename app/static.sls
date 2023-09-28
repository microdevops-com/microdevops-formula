{% if pillar["app"] is defined and "static" in pillar["app"] and "apps" in pillar["app"]["static"] %}

  {%- set app_type = "static" %}

  {%- include "app/_pkg.sls" with context %}
  {%- include "app/_pre_deploy.sls" with context %}

  {%- for app_name, app in pillar["app"]["static"]["apps"].items() %}
    {%- if not "deploy_only" in pillar["app"]["static"] or app_name == pillar["app"]["static"]["deploy_only"] %}

      {%- set loop_index = loop.index %}
      {%- set _app_user = app["user"]|replace("__APP_NAME__", app_name) %}
      {%- set _app_group = app["group"]|replace("__APP_NAME__", app_name) %}
      {%- set _app_app_root = app["app_root"]|replace("__APP_NAME__", app_name) %}

      {%- if app["user_home"] is defined %}
        {%- set consider_user_home = app["user_home"]|replace("__APP_NAME__", app_name) %}
      {%- else %}
        {%- set consider_user_home = _app_app_root %}
      {%- endif  %}

      {%- include "app/_user_and_source.sls" with context %}

      {%- include "app/_setup_scripts.sls" with context %}

      {%- include "app/_nginx.sls" with context %}

      {%- include "app/_logrotate.sls" with context %}

    {%- endif %}
  {%- endfor %}

  {%- include "app/_post_deploy.sls" with context %}

{% endif %}
