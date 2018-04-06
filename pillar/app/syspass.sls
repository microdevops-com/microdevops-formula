{#
this file should be included in pillar, which sets the following:
{% set appname = 'syspass' %}
{% set db_root_pass = 'XXX-set-db-root-pass-here-XXX' %}
{% set db_pass = 'XXX-set-syspass-db-pass-here-XXX' %}
{% set domain  = 'pass.example.com' %}

{% set syspass_version = '2.1.15.17101701' %}

cert is aquired via acme.sh which should be configured beforehand, set vars for it, e.g. for cloudflare
{% set acme_cf_key = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" %}
{% set acme_cf_email = "login@cloudflare.com" %}
{% set acme_mode = "--dns dns_cf" %}
{% include 'pkg/acme_cloudflare.jinja' with context %}
#}

percona:
  enabled: True
  version: 5.6
  root_password: '{{ db_root_pass }}'
  secure_install: True
  databases:
    - name: {{ appname }}
  users:
    {{ appname }}:
      host: localhost
      password: '{{ db_pass }}'
      databases:
        - database: {{ appname }}
          grant: ['all privileges']

nginx:
  enabled: True
  configs: 'nginx/app_hosting'

php-fpm:
  enabled: True
  version_5_6: True
  modules:
    php5_6:
      - php5.6-mysql
      - php5.6-curl
      - php5.6-zip
      - php5.6-gd
      - php5.6-mcrypt
      - php5.6-mbstring
      - php5.6-xml
      - php5.6-soap
      - php5.6-json
app:
  php-fpm_apps:
    {{ appname }}:
      enabled: True
      user: '{{ appname }}'
      group: '{{ appname }}'
      pass: '!'
      app_root: '/var/www/{{ appname }}'
      shell: '/bin/false'
      nginx:
        vhost_config: 'app/{{ appname }}/vhost.conf'
        root: '/var/www/{{ appname }}/sysPass'
        server_name: '{{ domain }}'
        server_name_301: 'www.{{ domain }}'
        access_log: '/var/log/nginx/{{ appname }}.access.log'
        error_log: '/var/log/nginx/{{ appname }}.error.log'
        ssl:
          acme: True
          acme_mode: '{{ acme_mode }}'
      pool:
        pool_config: 'app/{{ appname }}/pool.conf'
        php_version: '5.6'
        pm: |
          pm = ondemand
          pm.max_children = 50
          pm.process_idle_timeout = 10s
          pm.max_requests = 500
        php_admin: |
          php_admin_flag[html_errors] = off
          php_admin_value[post_max_size] = 25M
          php_admin_value[upload_max_filesize] = 25M
      source:
        enabled: True
        git: 'https://github.com/nuxsmin/sysPass.git'
        rev: '{{ syspass_version }}'
        target: '/var/www/{{ appname }}/sysPass'
        branch: 'master'
      setup_script:
        cwd: '/var/www/{{ appname }}/sysPass'
        name: 'chmod 750 config'
