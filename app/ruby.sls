{% if pillar["app"] is defined and "ruby" in pillar["app"] and "apps" in pillar["app"]["ruby"] %}

  {%- set app_type = "ruby" %}

  {%- include "app/_pkg.sls" with context %}

  {%- for app_name, app in pillar["app"]["ruby"]["apps"].items() %}
    {%- if not "deploy_only" in pillar["app"]["ruby"] or app_name == pillar["app"]["ruby"]["deploy_only"] %}

      {%- set loop_index = loop.index %}
      {%- set _app_user = app["user"]|replace("__APP_NAME__", app_name) %}
      {%- set _app_group = app["group"]|replace("__APP_NAME__", app_name) %}
      {%- set _app_app_root = app["app_root"]|replace("__APP_NAME__", app_name) %}

      {%- include "app/_user_and_source.sls" with context %}

      {%- if "npm" in app and "install" in app["npm"] %}
        {%- set i_loop = loop %}
        {%- for pkg in app["npm"]["install"] %}
app_ruby_app_npm_install_{{ i_loop.index}}_{{ loop.index }}:
  cmd.run:
    - cwd: {{ _app_app_root }}
    - runas: {{ _app_user }}
    - name: npm install {{ pkg }}

        {%- endfor %}
      {%- endif %}

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
      {%- if "bundle_install_cmd" in app["rvm"] %}
    - name: source {{ _app_app_root }}/.rvm/scripts/rvm && rvm use {{ app["rvm"]["version"] }} && {{ app["rvm"]["bundle_install_cmd"] }}
      {%- else %}
    - name: source {{ _app_app_root }}/.rvm/scripts/rvm && rvm use {{ app["rvm"]["version"] }} && bundle install
      {%- endif %}

      {%- endif %}

      {%- include "app/_setup_scripts.sls" with context %}

      {%- if "puma" in app %}
app_ruby_app_puma_root_{{ loop.index }}:
  cmd.run:
    - name: |
        loginctl enable-linger {{ _app_user }} && loginctl show-user {{ _app_user }}

app_ruby_app_puma_user_systemd_dir_{{ loop.index }}:
  file.directory:
    - name: {{ app["user_home"] if "user_home" in app else _app_app_root }}/.config/systemd/user
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - makedirs: True

app_ruby_app_puma_user_systemd_unit_file_{{ loop.index }}:
  file.managed:
    - name: {{ app["user_home"] if "user_home" in app else _app_app_root }}/.config/systemd/user/puma-{{ app_name }}.service
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - contents: |
        [Unit]
        Description=Puma HTTP Server
        After=network.target

        [Service]
        WorkingDirectory={{ app["puma"]["working_directory"]|replace("__APP_NAME__", app_name) }}
        ExecStart={{ app["puma"]["exec_start"]|replace("__APP_NAME__", app_name) }}
        Restart=always
        Environment=PUMA_DEBUG=1
        Environment=RAILS_ENV={{ app["puma"]["rails_env"] }}

        [Install]
        WantedBy=default.target

app_ruby_app_puma_user_systemd_unit_setup_{{ loop.index }}:
  cmd.run:
    - cwd: {{ _app_app_root }}
    - runas: {{ _app_user }}
    - name: |
        export XDG_RUNTIME_DIR=/run/user/$(id -u {{ _app_user }})
        systemctl --user daemon-reload
        systemctl --user enable --now puma-{{ app_name }}.service
        systemctl --user restart puma-{{ app_name }}.service
        systemctl --user status puma-{{ app_name }}.service

      {%- endif %}

      {%- if "unicorn" in app %}
app_ruby_app_unicorn_root_{{ loop.index }}:
  cmd.run:
    - name: |
        loginctl enable-linger {{ _app_user }} && loginctl show-user {{ _app_user }}

app_ruby_app_unicorn_user_systemd_dir_{{ loop.index }}:
  file.directory:
    - name: {{ app["user_home"] if "user_home" in app else _app_app_root }}/.config/systemd/user
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - makedirs: True

app_ruby_app_unicorn_user_systemd_unit_file_{{ loop.index }}:
  file.managed:
    - name: {{ app["user_home"] if "user_home" in app else _app_app_root }}/.config/systemd/user/unicorn-{{ app_name }}.service
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - contents: |
        [Unit]
        Description=Unicorn
        
        [Service]
        WorkingDirectory={{ app["unicorn"]["working_directory"]|replace("__APP_NAME__", app_name) }}
        Environment=RAILS_ENV={{ app["unicorn"]["rails_env"] }}
        ExecStart={{ app["unicorn"]["exec_start"]|replace("__APP_NAME__", app_name) }}
        Restart=always
        Type=forking
        
        [Install]
        WantedBy=default.target

app_ruby_app_unicorn_user_systemd_unit_setup_{{ loop.index }}:
  cmd.run:
    - cwd: {{ _app_app_root }}
    - runas: {{ _app_user }}
    - name: |
        export XDG_RUNTIME_DIR=/run/user/$(id -u {{ _app_user }})
        systemctl --user daemon-reload
        systemctl --user enable --now unicorn-{{ app_name }}.service
        systemctl --user restart unicorn-{{ app_name }}.service
        systemctl --user status unicorn-{{ app_name }}.service

      {%- endif %}

      {%- include "app/_nginx.sls" with context %}

      {%- include "app/_logrotate.sls" with context %}

    {%- endif %}
  {%- endfor %}
{% endif %}
