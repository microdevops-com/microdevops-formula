{% if (pillar['sentry'] is defined) and (pillar['sentry'] is not none) %}
  {%- if (pillar['sentry']['enabled'] is defined) and (pillar['sentry']['enabled'] is not none) and (pillar['sentry']['enabled']) %}
sentry_deps:
  pkg.installed:
    - pkgs:
      - libxml2-dev
      - libxslt1-dev
      - libffi-dev
      - libjpeg-dev
      - zlib1g-dev

sentry_group:
  group.present:
    - name: 'sentry'
    - addusers:
      - 'www-data'

sentry_user:
  user.present:
    - name: 'sentry'
    - gid: 'sentry'
    - home: '/opt/sentry'
    - createhome: True
    - password: '!'
    - shell: '/bin/bash'
    - fullname: 'sentry service'

sentry_virtualenv_dir:
  file.directory:
    - name: '/opt/sentry/env'
    - user: 'sentry'
    - group: 'sentry'
    - mode: 755
    - makedirs: True

sentry_etc_dir:
  file.directory:
    - name: '/opt/sentry/etc'
    - user: 'sentry'
    - group: 'sentry'
    - mode: 755
    - makedirs: True

sentry_log_dir:
  file.directory:
    - name: '/opt/sentry/log'
    - user: 'sentry'
    - group: 'sentry'
    - mode: 755
    - makedirs: True

sentry_run_dir:
  file.directory:
    - name: '/opt/sentry/run'
    - user: 'sentry'
    - group: 'sentry'
    - mode: 755
    - makedirs: True

sentry_data_dir:
  file.directory:
    - name: '/opt/sentry/data'
    - user: 'sentry'
    - group: 'sentry'
    - mode: 755
    - makedirs: True

sentry_www_dir:
  file.directory:
    - name: '/opt/sentry/www'
    - user: 'sentry'
    - group: 'sentry'
    - mode: 755
    - makedirs: True

sentry_virtualenv_python_version:
  file.managed:
    - name: '/opt/sentry/env/.python-version'
    - user: 'sentry'
    - group: 'sentry'
    - mode: '0644'
    - contents:
      - {{ pillar['sentry']['pyenv_version'] }}

sentry_virtualenv_pip:
  pip.installed:
    - name: 'virtualenv'
    - user: 'root'
    - cwd: '/tmp'
    - upgrade: True
    - bin_env: '/usr/local/pyenv/shims/pip'
    - env_vars:
        PYENV_VERSION: {{ pillar['sentry']['pyenv_version'] }}

sentry_virtualenv_bin:
  file.managed:
    - name: '/opt/sentry/virtualenv-{{ pillar['sentry']['pyenv_version'] }}'
    - user: 'sentry'
    - group: 'sentry'
    - source: 'salt://sentry/files/virtualenv'
    - template: jinja
    - defaults:
        pyenv_version: {{ pillar['sentry']['pyenv_version'] }}
    - mode: '0755'

sentry_supervisor_conf:
  file.managed:
    - name: '/etc/supervisor/conf.d/sentry.conf'
    - user: root
    - group: root
    - source: 'salt://sentry/files/supervisor_sentry.conf'

sentry_supervisor_reload:
  cmd.run:
    - runas: 'root'
    - name: 'supervisorctl reread && supervisorctl update && supervisorctl stop all'

sentry_req_txt:
  file.managed:
    - name: '/opt/sentry/requirements.txt'
    - user: 'sentry'
    - group: 'sentry'
    - source: 'salt://sentry/files/requirements.txt'
    - mode: '0644'

sentry_virtualenv:
  virtualenv.managed:
    - name: '/opt/sentry/env'
    - python: '/usr/local/pyenv/shims/python'
    - user: 'sentry'
    - cwd: '/opt/sentry'
    - system_site_packages: False
    - venv_bin: '/opt/sentry/virtualenv-{{ pillar['sentry']['pyenv_version'] }}'
    - env_vars:
        PYENV_VERSION: {{ pillar['sentry']['pyenv_version'] }}
    - requirements: '/opt/sentry/requirements.txt'
    - pip_upgrade: True

sentry_init:
  cmd.run:
    - name: '/opt/sentry/env/bin/sentry init /opt/sentry/etc && mv /opt/sentry/etc/config.yml /opt/sentry/etc/config.yml.orig && mv /opt/sentry/etc/sentry.conf.py /opt/sentry/etc/sentry.conf.py.orig'
    - cwd: '/opt/sentry'
    - runas: 'sentry'
    - unless: 'test -f /opt/sentry/etc/config.yml && test -f /opt/sentry/etc/sentry.conf.py'

sentry_config_1:
  file.managed:
    - name: '/opt/sentry/etc/config.yml'
    - user: 'sentry'
    - group: 'sentry'
    - mode: '0644'
    - source: 'salt://sentry/files/config.yml'
    - template: jinja
    - defaults:
        secret: {{ pillar['sentry']['secret'] }}
        admin_email: {{ pillar['sentry']['admin_email'] }}
        url: {{ pillar['sentry']['url'] }}
        email_user: {{ pillar['sentry']['email']['user'] }}
        email_host: {{ pillar['sentry']['email']['host'] }}
        email_port: {{ pillar['sentry']['email']['port'] }}
        email_pass: {{ pillar['sentry']['email']['pass'] }}
        email_tls: {{ pillar['sentry']['email']['tls'] }}

{# sentry.conf.py best doc is here: https://github.com/getsentry/sentry/blob/master/src/sentry/conf/server.py #}
sentry_config_2:
  file.managed:
    - name: '/opt/sentry/etc/sentry.conf.py'
    - user: 'sentry'
    - group: 'sentry'
    - mode: '0644'
    - source: 'salt://sentry/files/sentry.conf.py'
    - template: jinja
    - defaults:
        workers: {{ pillar['sentry']['workers'] }}
        pg_db: {{ pillar['sentry']['db']['db_name'] }}
        pg_user: {{ pillar['sentry']['db']['user'] }}
        pg_pass: {{ pillar['sentry']['db']['password'] }}
        pg_host: {{ pillar['sentry']['db']['host'] }}
        pg_port: {{ pillar['sentry']['db']['port'] }}

sentry_install_plugin:
  pip.installed:
    - name: 'sentry-plugins'
    - user: 'sentry'
    - cwd: '/tmp'
    - upgrade: True
    - bin_env: '/opt/sentry/env/bin/pip'
    - env_vars:
        PYENV_VERSION: {{ pillar['sentry']['pyenv_version'] }}

    {%- if (pillar['sentry']['plugins'] is defined) and (pillar['sentry']['plugins'] is not none) %}
      {%- for plugin in pillar['sentry']['plugins']|sort %}
sentry_install_plugin_{{ loop.index }}:
  pip.installed:
    - name: '{{ plugin }}'
    - user: 'sentry'
    - cwd: '/tmp'
    - upgrade: True
    - bin_env: '/opt/sentry/env/bin/pip'
    - env_vars:
        PYENV_VERSION: {{ pillar['sentry']['pyenv_version'] }}

      {%- endfor %}
    {%- endif %}

sentry_upgrade:
  cmd.run:
    - name: 'SENTRY_CONF=/opt/sentry/etc /opt/sentry/env/bin/sentry upgrade --noinput'
    - cwd: '/opt/sentry'
    - runas: 'sentry'

sentry_superuser:
  cmd.run:
    - name: '( echo "select id from auth_user where email = ''{{ pillar['sentry']['admin_email'] }}'' and is_superuser is true" | su -l postgres -c "psql sentry" | grep -q "(0 row)" ) && su -l sentry -c "SENTRY_CONF=/opt/sentry/etc /opt/sentry/env/bin/sentry createuser --email ''{{ pillar['sentry']['admin_email'] }}'' --password ''{{ pillar['sentry']['admin_password'] }}'' --superuser --no-input" || true'
    - runas: 'root'

sentry_supervisor_start:
  cmd.run:
    - runas: 'root'
    - name: 'supervisorctl start all'

sentry_nginx_vhost_config_snake:
  file.managed:
    - name: '/etc/nginx/sites-available/sentry.conf'
    - user: root
    - group: root
    - source: 'salt://sentry/files/vhost.conf'
    - template: jinja
    - defaults:
        server_name: '{{ pillar['sentry']['nginx']['server_name'] }}'
        server_name_301: '{{ pillar['sentry']['nginx']['server_name_301'] }}'
        access_log: '{{ pillar['sentry']['nginx']['access_log'] }}'
        error_log: '{{ pillar['sentry']['nginx']['error_log'] }}'
        url: '{{ pillar['sentry']['url'] }}'
        ssl_cert: '/etc/ssl/certs/ssl-cert-snakeoil.pem'
        ssl_key: '/etc/ssl/private/ssl-cert-snakeoil.key'

sentry_nginx_vhost_symlink:
  file.symlink:
    - name: '/etc/nginx/sites-enabled/sentry.conf'
    - target: '/etc/nginx/sites-available/sentry.conf'

sentry_nginx_reload:
  cmd.run:
    - runas: 'root'
    - name: 'service nginx configtest && service nginx restart'

sentry_certbot_dir:
  file.directory:
    - name: '/opt/sentry/www/certbot/.well-known'
    - user: 'sentry'
    - group: 'sentry'
    - makedirs: True

    {%- set cert_dom = pillar['sentry']['nginx']['server_name'] ~ ' ' ~ pillar['sentry']['nginx']['server_name_301'] %}
sentry_certbot_run:
  cmd.run:
    - runas: 'root'
    - name: '/opt/certbot/certbot-auto -n certonly --webroot --reinstall --allow-subset-of-names --agree-tos --cert-name sentry --email {{ pillar['sentry']['nginx']['certbot_email'] }} -w /opt/sentry/www/certbot -d "{{ cert_dom|replace(" ", ",") }}"'

sentry_nginx_vhost_config:
  file.managed:
    - name: '/etc/nginx/sites-available/sentry.conf'
    - user: root
    - group: root
    - source: 'salt://sentry/files/vhost.conf'
    - template: jinja
    - defaults:
        server_name: '{{ pillar['sentry']['nginx']['server_name'] }}'
        server_name_301: '{{ pillar['sentry']['nginx']['server_name_301'] }}'
        access_log: '{{ pillar['sentry']['nginx']['access_log'] }}'
        error_log: '{{ pillar['sentry']['nginx']['error_log'] }}'
        url: '{{ pillar['sentry']['url'] }}'
        ssl_cert: '/etc/letsencrypt/live/sentry/fullchain.pem'
        ssl_key: '/etc/letsencrypt/live/sentry/privkey.pem'

sentry_nginx_reload_2:
  cmd.run:
    - runas: 'root'
    - name: 'service nginx configtest && service nginx restart'

sentry_certbot_cron:
  cron.present:
    - name: '/opt/certbot/certbot-auto renew --renew-hook "service nginx configtest && service nginx restart"'
    - identifier: 'certbot_cron'
    - user: root
    - minute: 10
    - hour: 2
    - dayweek: 1

sentry_cleanup_cron:
  cron.present:
    - name: 'SENTRY_CONF=/opt/sentry/etc /opt/sentry/env/bin/sentry cleanup --days=30'
    - identifier: 'sentry_cleanup_cron'
    - user: sentry
    - minute: 15
    - hour: 1

  {%- endif %}
{%- endif %}
