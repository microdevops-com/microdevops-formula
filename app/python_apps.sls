{% if (pillar['app'] is defined) and (pillar['app'] is not none) %}
  {%- if (pillar['app']['python_apps'] is defined) and (pillar['app']['python_apps'] is not none) %}
    {%- if (pillar['certbot_staging'] is defined) and (pillar['certbot_staging'] is not none) and (pillar['certbot_staging']) %}
      {%- set certbot_staging = "--staging" %}
    {%- else %}
      {%- set certbot_staging = " " %}
    {%- endif %}
    {%- if (pillar['certbot_force_renewal'] is defined) and (pillar['certbot_force_renewal'] is not none) and (pillar['certbot_force_renewal']) %}
      {%- set certbot_force_renewal = "--force-renewal" %}
    {%- else %}
      {%- set certbot_force_renewal = " " %}
    {%- endif %}
    {%- if (pillar['app_only_one'] is defined) and (pillar['app_only_one'] is not none) %}
      {%- set app_selector = pillar['app_only_one'] %}
    {%- else %}
      {%- set app_selector = 'all' %}
    {%- endif %}
    {%- for python_app, app_params in pillar['app']['python_apps'].items() -%}
      {%- if
             (app_params['enabled'] is defined) and (app_params['enabled'] is not none) and (app_params['enabled']) and
             (app_params['user'] is defined) and (app_params['user'] is not none) and
             (app_params['group'] is defined) and (app_params['group'] is not none) and
             (app_params['app_root'] is defined) and (app_params['app_root'] is not none) and
             (app_params['shell'] is defined) and (app_params['shell'] is not none) and

             (app_params['nginx'] is defined) and (app_params['nginx'] is not none) and
             (app_params['nginx']['vhost_config'] is defined) and (app_params['nginx']['vhost_config'] is not none) and
             (app_params['nginx']['root'] is defined) and (app_params['nginx']['root'] is not none) and
             (app_params['nginx']['server_name'] is defined) and (app_params['nginx']['server_name'] is not none) and
             (app_params['nginx']['access_log'] is defined) and (app_params['nginx']['access_log'] is not none) and
             (app_params['nginx']['error_log'] is defined) and (app_params['nginx']['error_log'] is not none) and

             (
               (app_selector == 'all') or
               (app_selector == python_app)
             )
      %}
python_apps_group_{{ loop.index }}:
  group.present:
    - name: {{ app_params['group'] }}

python_apps_user_homedir_{{ loop.index }}:
  file.directory:
    - name: {{ app_params['app_root'] }}
    - makedirs: True

python_apps_user_{{ loop.index }}:
  user.present:
    - name: {{ app_params['user'] }}
    - gid: {{ app_params['group'] }}
    - home: {{ app_params['app_root'] }}
    - createhome: True
    {% if app_params['pass'] == '!' %}
    - password: '{{ app_params['pass'] }}'
    {% else %}
    - password: '{{ app_params['pass'] }}'
    - hash_password: True
    {% endif %}
    - shell: {{ app_params['shell'] }}
    - fullname: {{ 'application ' ~ python_app }}

python_apps_user_homedir_userown_{{ loop.index }}:
  file.directory:
    - name: {{ app_params['app_root'] }}
    - user: {{ app_params['user'] }}
    - group: {{ app_params['group'] }}
    - makedirs: True

python_apps_nginx_root_dir_{{ loop.index }}:
  file.directory:
    - name: {{ app_params['nginx']['root'] }}
    - user: {{ app_params['user'] }}
    - group: {{ app_params['group'] }}
    - mode: 755
    - makedirs: True

python_apps_user_ssh_dir_{{ loop.index }}:
  file.directory:
    - name: {{ app_params['app_root'] ~ '/.ssh' }}
    - user: {{ app_params['user'] }}
    - group: {{ app_params['group'] }}
    - mode: 700
    - makedirs: True

        {%- if (app_params['app_auth_keys'] is defined) and (app_params['app_auth_keys'] is not none) %}
python_apps_user_ssh_auth_keys_{{ loop.index }}:
  file.managed:
    - name: {{ app_params['app_root'] ~ '/.ssh/authorized_keys' }}
    - user: {{ app_params['user'] }}
    - group: {{ app_params['group'] }}
    - mode: 600
    - contents: {{ app_params['app_auth_keys'] | yaml_encode }}
        {%- endif %}

        {%- if
               (app_params['source'] is defined) and (app_params['source'] is not none) and
               (app_params['source']['enabled'] is defined) and (app_params['source']['enabled'] is not none) and (app_params['source']['enabled']) and
               (
                 ((app_params['source']['git'] is defined) and (app_params['source']['git'] is not none)) or
                 ((app_params['source']['hg'] is defined) and (app_params['source']['hg'] is not none))
               ) and
               (app_params['source']['rev'] is defined) and (app_params['source']['rev'] is not none) and
               (app_params['source']['target'] is defined) and (app_params['source']['target'] is not none)
        %}

          {%- if
                 (app_params['source']['repo_key'] is defined) and (app_params['source']['repo_key'] is not none) and
                 (app_params['source']['repo_key_pub'] is defined) and (app_params['source']['repo_key_pub'] is not none)
          %}
python_apps_user_ssh_id_{{ loop.index }}:
  file.managed:
    - name: {{ app_params['app_root'] ~ '/.ssh/id_repo' }}
    - user: {{ app_params['user'] }}
    - group: {{ app_params['group'] }}
    - mode: '0600'
    - contents: {{ app_params['source']['repo_key'] | yaml_encode }}

python_apps_user_ssh_id_pub_{{ loop.index }}:
  file.managed:
    - name: {{ app_params['app_root'] ~ '/.ssh/id_repo.pub' }}
    - user: {{ app_params['user'] }}
    - group: {{ app_params['group'] }}
    - mode: '0600'
    - contents: {{ app_params['source']['repo_key_pub'] | yaml_encode }}

python_apps_user_ssh_config_{{ loop.index }}:
  file.managed:
    - name: {{ app_params['app_root'] ~ '/.ssh/config' }}
    - user: {{ app_params['user'] }}
    - group: {{ app_params['group'] }}
    - mode: '0600'
    - contents: {{ app_params['source']['ssh_config'] | yaml_encode }}
          {%- endif %}

python_apps_app_checkout_{{ loop.index }}:
          {%- if (app_params['source']['git'] is defined) and (app_params['source']['git'] is not none) %}
  git.latest:
    - name: {{ app_params['source']['git'] }}
    - rev: {{ app_params['source']['rev'] }}
    - target: {{ app_params['source']['target'] }}
    - branch: {{ app_params['source']['branch'] }}
    - force_reset: True
    - force_fetch: True
    - user: {{ app_params['user'] }}
          {%- elif (app_params['source']['hg'] is defined) and (app_params['source']['hg'] is not none)  %}
  hg.latest:
    - name: {{ app_params['source']['hg'] }}
    - rev: {{ app_params['source']['rev'] }}
    - target: {{ app_params['source']['target'] }}
    - user: {{ app_params['user'] }}
          {%- endif %}
          {%- if
                 (app_params['source']['repo_key'] is defined) and (app_params['source']['repo_key'] is not none) and
                 (app_params['source']['repo_key_pub'] is defined) and (app_params['source']['repo_key_pub'] is not none)
          %}
    - identity: {{ app_params['app_root'] ~ '/.ssh/id_repo' }}
          {%- endif %}
        {%- endif %}

        {%- if
               (app_params['files'] is defined) and (app_params['files'] is not none) and
               (app_params['files']['src'] is defined) and (app_params['files']['src'] is not none) and
               (app_params['files']['dst'] is defined) and (app_params['files']['dst'] is not none)
        %}
python_apps_app_files_{{ loop.index }}:
  file.recurse:
    - name: {{ app_params['files']['dst'] }}
    - source: {{ 'salt://' ~ app_params['files']['src'] }}
    - clean: False
    - user: {{ app_params['user'] }}
    - group: {{ app_params['group'] }}
    - dir_mode: 755
    - file_mode: 644
        {%- endif %}

        {%- if
               (app_params['virtualenv'] is defined) and (app_params['virtualenv'] is not none) and
               (app_params['virtualenv']['pyenv_version'] is defined) and (app_params['virtualenv']['pyenv_version'] is not none) and
               (app_params['virtualenv']['target'] is defined) and (app_params['virtualenv']['target'] is not none)
        %}
python_apps_app_virtualenv_dir_{{ loop.index }}:
  file.directory:
    - name: {{ app_params['virtualenv']['target'] }}
    - user: {{ app_params['user'] }}
    - group: {{ app_params['group'] }}
    - mode: 755
    - makedirs: True

python_apps_app_virtualenv_python_version_{{ loop.index }}:
  file.managed:
    - name: {{ app_params['virtualenv']['target'] ~ '/.python-version' }}
    - user: {{ app_params['user'] }}
    - group: {{ app_params['group'] }}
    - mode: '0644'
    - contents:
      - {{ app_params['virtualenv']['pyenv_version'] }}

python_apps_app_virtualenv_pip_{{ loop.index }}:
  pip.installed:
    - name: virtualenv
    - user: root
    - cwd: /tmp
    - bin_env: /usr/local/pyenv/shims/pip
    - env_vars:
        PYENV_VERSION: {{ app_params['virtualenv']['pyenv_version'] }}

python_apps_app_virtualenv_bin_{{ loop.index }}:
  file.managed:
    - name: {{ app_params['app_root'] ~ '/virtualenv-' ~ app_params['virtualenv']['pyenv_version'] }}
    - user: {{ app_params['user'] }}
    - group: {{ app_params['group'] }}
    - mode: '0755'
    - contents: |
        #!/bin/sh
        export PYENV_VERSION='{{ app_params["virtualenv"]["pyenv_version"] }}'
        /usr/local/pyenv/shims/virtualenv "$@"

python_apps_app_virtualenv_{{ loop.index }}:
  virtualenv.managed:
    - name: {{ app_params['virtualenv']['target'] }}
    - python: /usr/local/pyenv/shims/python
    - user: {{ app_params['user'] }}
    - cwd: {{ app_params['group'] }}
    - system_site_packages: False
    - venv_bin: {{ app_params['app_root'] ~ '/virtualenv-' ~ app_params['virtualenv']['pyenv_version'] }}
    - env_vars:
        PYENV_VERSION: {{ app_params['virtualenv']['pyenv_version'] }}
        {%- endif %}

        {%- if
               (app_params['setup_script'] is defined) and (app_params['setup_script'] is not none) and
               (app_params['setup_script']['cwd'] is defined) and (app_params['setup_script']['cwd'] is not none) and
               (app_params['setup_script']['name'] is defined) and (app_params['setup_script']['name'] is not none)
        %}
python_apps_app_setup_script_run_{{ loop.index }}:
  cmd.run:
    - cwd: {{ app_params['setup_script']['cwd'] }}
    - name: {{ app_params['setup_script']['name'] }}
    - runas: {{ app_params['user'] }}
        {%- endif %}

        {%- if
               (app_params['nginx']['auth_basic'] is defined) and (app_params['nginx']['auth_basic'] is not none) and
               (app_params['nginx']['auth_basic']['user'] is defined) and (app_params['nginx']['auth_basic']['user'] is not none) and
               (app_params['nginx']['auth_basic']['pass'] is defined) and (app_params['nginx']['auth_basic']['pass'] is not none)
        %}
python_apps_app_apache_utils_{{ loop.index }}:
  pkg.installed:
    - pkgs:
      - apache2-utils

python_apps_app_htaccess_user_{{ loop.index }}:
  webutil.user_exists:
    - name: '{{ app_params['nginx']['auth_basic']['user'] }}'
    - password: '{{ app_params['nginx']['auth_basic']['pass'] }}'
    - htpasswd_file: '{{ app_params['app_root'] }}/.htpasswd'
    - force: True
    - runas: {{ app_params['user'] }}

          {%- set auth_basic_block = 'auth_basic "Restricted Content"; auth_basic_user_file ' ~ app_params['app_root'] ~ '/.htpasswd;' %}
        {%- else %}
          {%- set auth_basic_block = ' ' %}
        {%- endif %}

python_apps_nginx_sites_dir_{{ loop.index }}:
  file.directory:
    - name: '/etc/nginx/sites-available'
    - makedirs: True

        {%- if (app_params['nginx']['ssl'] is defined) and (app_params['nginx']['ssl'] is not none) %}
python_apps_app_nginx_ssl_dir_{{ loop.index }}:
  file.directory:
    - name: '/etc/nginx/ssl/{{ python_app }}'
    - user: root
    - group: root
    - makedirs: True
        {%- endif %}

        {%- set server_name_301 = app_params['nginx'].get('server_name_301', python_app ~ '.example.com') %}
        {%- if
               (app_params['nginx']['ssl'] is defined) and (app_params['nginx']['ssl'] is not none) and
               (app_params['nginx']['ssl']['cert'] is defined) and (app_params['nginx']['ssl']['cert'] is not none) and
               (app_params['nginx']['ssl']['key'] is defined) and (app_params['nginx']['ssl']['key'] is not none) and
               (app_params['nginx']['ssl']['chain'] is defined) and (app_params['nginx']['ssl']['chain'] is not none)
        %}
python_apps_app_nginx_ssl_certs_dir_{{ loop.index }}:
  file.directory:
    - name: '/etc/nginx/ssl/{{ python_app }}'
    - user: root
    - group: root
    - dir_mode: 700
    - makedirs: True

python_apps_app_nginx_ssl_certs_cert_{{ loop.index }}:
  file.managed:
    - name: '/etc/nginx/ssl/{{ python_app }}/{{ python_app }}.crt'
    - user: root
    - group: root
    - mode: '0600'
    - contents: {{ app_params['nginx']['ssl']['cert'] | yaml_encode }}

python_apps_app_nginx_ssl_certs_key_{{ loop.index }}:
  file.managed:
    - name: '/etc/nginx/ssl/{{ python_app }}/{{ python_app }}.key'
    - user: root
    - group: root
    - mode: '0600'
    - contents: {{ app_params['nginx']['ssl']['key'] | yaml_encode }}

python_apps_app_nginx_ssl_certs_chain_{{ loop.index }}:
  file.managed:
    - name: '/etc/nginx/ssl/{{ python_app }}/chain.crt'
    - user: root
    - group: root
    - mode: '0600'
    - contents: {{ app_params['nginx']['ssl']['chain'] | yaml_encode }}

python_apps_app_nginx_vhost_config_{{ loop.index }}:
  file.managed:
    - name: '/etc/nginx/sites-available/{{ python_app }}.conf'
    - user: root
    - group: root
    - source: 'salt://{{ app_params['nginx']['vhost_config'] }}'
    - template: jinja
    - defaults:
        server_name: {{ app_params['nginx']['server_name'] }}
        server_name_301: '{{ server_name_301 }}'
        nginx_root: {{ app_params['nginx']['root'] }}
        access_log: {{ app_params['nginx']['access_log'] }}
        error_log: {{ app_params['nginx']['error_log'] }}
        app_name: {{ python_app }}
        app_root: {{ app_params['app_root'] }}
        ssl_cert: '/etc/nginx/ssl/{{ python_app }}/{{ python_app }}.crt'
        ssl_key: '/etc/nginx/ssl/{{ python_app }}/{{ python_app }}.key'
        ssl_chain: '/etc/nginx/ssl/{{ python_app }}/chain.crt'
        ssl_cert_301: '/etc/nginx/ssl/{{ python_app }}/301_fullchain.pem'
        ssl_key_301: '/etc/nginx/ssl/{{ python_app }}/301_privkey.pem'
        auth_basic_block: '{{ auth_basic_block }}'

          {%- if not salt['file.file_exists']('/etc/nginx/ssl/' ~ python_app ~ '/301_fullchain.pem') %}
python_apps_app_nginx_ssl_link_1_{{ loop.index }}:
  file.symlink:
    - name: '/etc/nginx/ssl/{{ python_app }}/301_fullchain.pem'
    - target: '/etc/ssl/certs/ssl-cert-snakeoil.pem'
          {%- endif %}

          {%- if not salt['file.file_exists']('/etc/nginx/ssl/' ~ python_app ~ '/301_privkey.pem') %}
python_apps_app_nginx_ssl_link_2_{{ loop.index }}:
  file.symlink:
    - name: '/etc/nginx/ssl/{{ python_app }}/301_privkey.pem'
    - target: '/etc/ssl/private/ssl-cert-snakeoil.key'
          {%- endif %}

          {%- if
                 (app_params['nginx']['ssl']['certbot_for_301'] is defined) and (app_params['nginx']['ssl']['certbot_for_301'] is not none) and (app_params['nginx']['ssl']['certbot_for_301']) and
                 (app_params['nginx']['ssl']['certbot_email'] is defined) and (app_params['nginx']['ssl']['certbot_email'] is not none) and
                 (pillar['certbot_run_ready'] is defined) and (pillar['certbot_run_ready'] is not none) and (pillar['certbot_run_ready'])
          %}
python_apps_app_certbot_dir_{{ loop.index }}:
  file.directory:
    - name: '{{ app_params['app_root'] }}/certbot/.well-known'
    - user: {{ app_params['user'] }}
    - group: {{ app_params['group'] }}
    - makedirs: True

python_apps_app_certbot_run_{{ loop.index }}:
  cmd.run:
    - cwd: /root
    - name: '/opt/certbot/certbot-auto -n certonly --webroot {{ certbot_staging }} {{ certbot_force_renewal }} --reinstall --allow-subset-of-names --agree-tos --cert-name {{ python_app }} --email {{ app_params['nginx']['ssl']['certbot_email'] }} -w {{ app_params['app_root'] }}/certbot -d "{{ server_name_301|replace(" ", ",") }}"'

python_apps_app_certbot_replace_symlink_1_{{ loop.index }}:
  cmd.run:
    - cwd: /root
    - name: 'test -f /etc/letsencrypt/live/{{ python_app }}/fullchain.pem && ln -s -f /etc/letsencrypt/live/{{ python_app }}/fullchain.pem /etc/nginx/ssl/{{ python_app }}/301_fullchain.pem || true'

python_apps_app_certbot_replace_symlink_2_{{ loop.index }}:
  cmd.run:
    - cwd: /root
    - name: 'test -f /etc/letsencrypt/live/{{ python_app }}/privkey.pem && ln -s -f /etc/letsencrypt/live/{{ python_app }}/privkey.pem /etc/nginx/ssl/{{ python_app }}/301_privkey.pem || true'

python_apps_app_certbot_cron_{{ loop.index }}:
  cron.present:
    - name: '/opt/certbot/certbot-auto renew --renew-hook "service nginx configtest && service nginx restart"'
    - identifier: 'certbot_cron'
    - user: root
    - minute: 10
    - hour: 2
    - dayweek: 1
          {%- endif %}

        {%- elif
               (app_params['nginx']['ssl'] is defined) and (app_params['nginx']['ssl'] is not none) and
               (app_params['nginx']['ssl']['certbot'] is defined) and (app_params['nginx']['ssl']['certbot'] is not none) and (app_params['nginx']['ssl']['certbot']) and
               (app_params['nginx']['ssl']['certbot_email'] is defined) and (app_params['nginx']['ssl']['certbot_email'] is not none)
        %}
python_apps_app_nginx_vhost_config_{{ loop.index }}:
  file.managed:
    - name: '/etc/nginx/sites-available/{{ python_app }}.conf'
    - user: root
    - group: root
    - source: 'salt://{{ app_params['nginx']['vhost_config'] }}'
    - template: jinja
    - defaults:
        server_name: {{ app_params['nginx']['server_name'] }}
        server_name_301: '{{ server_name_301 }}'
        nginx_root: {{ app_params['nginx']['root'] }}
        access_log: {{ app_params['nginx']['access_log'] }}
        error_log: {{ app_params['nginx']['error_log'] }}
        app_name: {{ python_app }}
        app_root: {{ app_params['app_root'] }}
        ssl_cert: '/etc/nginx/ssl/{{ python_app }}/fullchain.pem'
        ssl_key: '/etc/nginx/ssl/{{ python_app }}/privkey.pem'
        auth_basic_block: '{{ auth_basic_block }}'

          {%- if not salt['file.file_exists']('/etc/nginx/ssl/' ~ python_app ~ '/fullchain.pem') %}
python_apps_app_nginx_ssl_link_1_{{ loop.index }}:
  file.symlink:
    - name: '/etc/nginx/ssl/{{ python_app }}/fullchain.pem'
    - target: '/etc/ssl/certs/ssl-cert-snakeoil.pem'
          {%- endif %}

          {%- if not salt['file.file_exists']('/etc/nginx/ssl/' ~ python_app ~ '/privkey.pem') %}
python_apps_app_nginx_ssl_link_2_{{ loop.index }}:
  file.symlink:
    - name: '/etc/nginx/ssl/{{ python_app }}/privkey.pem'
    - target: '/etc/ssl/private/ssl-cert-snakeoil.key'
          {%- endif %}

          {%- if (pillar['certbot_run_ready'] is defined) and (pillar['certbot_run_ready'] is not none) and (pillar['certbot_run_ready']) %}
python_apps_app_certbot_dir_{{ loop.index }}:
  file.directory:
    - name: '{{ app_params['app_root'] }}/certbot/.well-known'
    - user: {{ app_params['user'] }}
    - group: {{ app_params['group'] }}
    - makedirs: True

python_apps_app_certbot_run_{{ loop.index }}:
  cmd.run:
    - cwd: /root
    - name: '/opt/certbot/certbot-auto -n certonly --webroot {{ certbot_staging }} {{ certbot_force_renewal }} --reinstall --allow-subset-of-names --agree-tos --cert-name {{ python_app }} --email {{ app_params['nginx']['ssl']['certbot_email'] }} -w {{ app_params['app_root'] }}/certbot -d "{{ app_params['nginx']['server_name']|replace(" ", ",") }}"'

python_apps_app_certbot_replace_symlink_1_{{ loop.index }}:
  cmd.run:
    - cwd: /root
    - name: 'test -f /etc/letsencrypt/live/{{ python_app }}/fullchain.pem && ln -s -f /etc/letsencrypt/live/{{ python_app }}/fullchain.pem /etc/nginx/ssl/{{ python_app }}/fullchain.pem || true'

python_apps_app_certbot_replace_symlink_2_{{ loop.index }}:
  cmd.run:
    - cwd: /root
    - name: 'test -f /etc/letsencrypt/live/{{ python_app }}/privkey.pem && ln -s -f /etc/letsencrypt/live/{{ python_app }}/privkey.pem /etc/nginx/ssl/{{ python_app }}/privkey.pem || true'

python_apps_app_certbot_cron_{{ loop.index }}:
  cron.present:
    - name: '/opt/certbot/certbot-auto renew --renew-hook "service nginx configtest && service nginx restart"'
    - identifier: 'certbot_cron'
    - user: root
    - minute: 10
    - hour: 2
    - dayweek: 1
          {%- endif %}

        {%- else %}
python_apps_app_nginx_vhost_config_{{ loop.index }}:
  file.managed:
    - name: '/etc/nginx/sites-available/{{ python_app }}.conf'
    - user: root
    - group: root
    - source: 'salt://{{ app_params['nginx']['vhost_config'] }}'
    - template: jinja
    - defaults:
        server_name: {{ app_params['nginx']['server_name'] }}
        server_name_301: '{{ server_name_301 }}'
        nginx_root: {{ app_params['nginx']['root'] }}
        access_log: {{ app_params['nginx']['access_log'] }}
        error_log: {{ app_params['nginx']['error_log'] }}
        app_name: {{ python_app }}
        app_root: {{ app_params['app_root'] }}
        auth_basic_block: '{{ auth_basic_block }}'
        {%- endif %}

        {%- if (pillar['nginx_reload'] is defined) and (pillar['nginx_reload'] is not none) and (pillar['nginx_reload']) %}
python_apps__nginx_reload__{{ loop.index }}:
  cmd.run:
    - runas: 'root'
    - name: 'service nginx configtest && service nginx reload'

        {%- endif %}
      {%- endif %}
    {%- endfor %}

python_apps_info_warning:
  test.configurable_test_state:
    - name: state_warning
    - changes: False
    - result: True
    - comment: |
        WARNING: State configures nginx virtual hosts, BUT it doesn't reload or restart nginx, apps.
        WARNING: It is done so not to break running production sites on the host.
         NOTICE:
         NOTICE: You should state.apply this state first, then check configs, reload or restart nginx, pfp-fpm manually.
         NOTICE: After that there will be /.well-known/ location ready to serve certbot request.
         NOTICE:
         NOTICE: For the second time you can run:
         NOTICE: state.apply ... pillar='{"certbot_run_ready": True}'
         NOTICE: This will activate certbot execution and active its certs in nginx.
         NOTICE:
         NOTICE: After that you can check and reload again.
         NOTICE:
         NOTICE: Also, not to be temp banned by LE when making test runs, you can run:
         NOTICE: state.apply ... pillar='{"certbot_run_ready": True, "certbot_staging": True}'
         NOTICE: This will add --staging option to certbot. Certificate will be not trusted, but LE will allow much more tests.
         NOTICE:
         NOTICE: After staging experiments you can force renewal with:
         NOTICE: state.apply ... pillar='{"certbot_run_ready": True, "certbot_force_renewal": True}'
         NOTICE: This will add --force-renewal option to certbot.
         NOTICE:
         NOTICE: You can run only one app with pillar:
         NOTICE: state.apply ... pillar='{"app_only_one": "<app_name>"}'
         NOTICE:
         NOTICE: You can run 'service nginx configtest && service nginx reload' after each app deploy with pillar:
         NOTICE: state.apply ... pillar='{"nginx_reload": True}'
  {%- endif %}
{%- endif %}
