{% if pillar["app"] is defined and "ruby" in pillar["app"] %}

  {%- include "app/_pkg.sls" with context %}

  {%- for app_name, app in pillar["app"]["ruby"]["apps"].items() %}
    {%- if not "deploy_only" in pillar["app"]["ruby"] or app_name in pillar["app"]["ruby"]["deploy_only"] %}

      {%- set app_type = "ruby" %}
      {%- set loop_index = loop.index %}
      {%- set _app_user = app["user"]|replace("__APP_NAME__", app_name) %}
      {%- set _app_group = app["group"]|replace("__APP_NAME__", app_name) %}
      {%- set _app_app_root = app["app_root"]|replace("__APP_NAME__", app_name) %}

      {%- include "app/_user_and_source.sls" with context %}

      {%- if "rvm" in app %}
# Do not try to use Multi User or Mixed Mode - it will drive you crazy and will not work anyway :) spent 2 days on this.
# Single User will take extra space for each app, but at least works.
app_ruby_app_rvm_install_keys_{{ loop.index }}:
  cmd.run:
    - cwd: {{ _app_app_root }}
    - runas: {{ _app_user }}
    - name: curl -sSL https://rvm.io/mpapis.asc | gpg --import - ; curl -sSL https://rvm.io/pkuczynski.asc | gpg --import -

# With autolibs feature rvm tries to install depencies with sudo, which we are not going to give.
# If some libs are missing - it will show "Missing required packages:", add them to app:pkg pillar.
app_ruby_app_rvm_install_{{ loop.index }}:
  cmd.run:
    - cwd: {{ _app_app_root }}
    - runas: {{ _app_user }}
    - name: curl -sSL https://get.rvm.io | bash -s -- --autolibs=read-fail

app_ruby_app_rvm_install_ruby_{{ loop.index }}:
  cmd.run:
    - cwd: {{ _app_app_root }}
    - runas: {{ _app_user }}
    - name: rvm install {{ app["rvm"]["version"] }}

app_ruby_app_rvm_update_bundler_{{ loop.index }}:
  cmd.run:
    - cwd: {{ _app_app_root }}
    - runas: {{ _app_user }}
    - name: source {{ _app_app_root }}/.rvm/scripts/rvm && rvm use {{ app["rvm"]["version"] }} && gem update bundler

app_ruby_app_rvm_bundle_install_{{ loop.index }}:
  cmd.run:
    - cwd: {{ app["rvm"]["bundle_install"]|replace("__APP_NAME__", app_name) }}
    - runas: {{ _app_user }}
    - name: source {{ _app_app_root }}/.rvm/scripts/rvm && rvm use {{ app["rvm"]["version"] }} && bundle install

      {%- endif %}

      {%- include "app/_setup_scripts.sls" with context %}

      {%- include "app/_nginx.sls" with context %}

    {%- endif %}
  {%- endfor %}
{% endif %}
