{% if (pillar['sentry'] is defined) and (pillar['sentry'] is not none) %}
  {%- if (pillar['sentry']['enabled'] is defined) and (pillar['sentry']['enabled'] is not none) and (pillar['sentry']['enabled']) %}
sentry_packages:
  pkg.installed:
    - pkgs:
      - python-setuptools
      - python-memcache
      - python-psycopg2
      - python-imaging
      - python-docutils
      - python-simplejson
      - build-essential
      - gettext
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
    - requirements: salt://sentry/files/requirements.txt
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

{# sentry.conf.py best doc is here: https://github.com/getsentry/sentry/blob/master/src/sentry/conf/server.py #}
sentry_config_2:
  file.managed:
    - name: '/opt/sentry/etc/sentry.conf.py'
    - user: 'sentry'
    - group: 'sentry'
    - mode: '0644'
    - source: 'salt://sentry/files/sentry.conf.py'
    - template: jinja

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

sentry_cleanup_cron:
  cron.present:
    - name: 'SENTRY_CONF=/opt/sentry/etc /opt/sentry/env/bin/sentry cleanup --days=30'
    - identifier: 'sentry_cleanup_cron'
    - user: sentry
    - minute: 15
    - hour: 1

  {%- endif %}
{%- endif %}
