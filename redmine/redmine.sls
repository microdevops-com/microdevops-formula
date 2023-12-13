{% if pillar['redmine'] is defined and pillar['redmine'] is not none %}

{# ### START docker section #}

  {%- if pillar["docker-ce"] is not defined %}
    {%- set docker_ce = {"version": pillar["redmine"]["docker-ce_version"],
                         "daemon_json": '{"iptables": false}'} %}
  {%- endif %}
  {%- include "docker-ce/docker-ce.sls" with context %}

redmine_etc_dir:
  file.directory:
    - name: /opt/redmine/{{ pillar['redmine']['domain'] }}/config
    - mode: 755
    - makedirs: True

redmine_data_dir:
  file.directory:
    - name: /opt/redmine/{{ pillar['redmine']['domain'] }}/files
    - mode: 755
    - makedirs: True

redmine_configuration_file:
  file.managed:
    - name: /opt/redmine/{{ pillar['redmine']['domain'] }}/config/configuration.yml
    - mode: 644
    - makedirs: True
    - contents: {{ pillar['redmine']['configuration'] | yaml_encode }}

redmine_image:
  cmd.run:
    - name: docker pull {{ pillar['redmine']['image'] }}

redmine_container:
  docker_container.running:
    - name: {{ pillar['redmine']['name'] }}
    - user: root
    - image: {{ pillar['redmine']['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - 127.0.0.1:3000:3000/tcp
    - binds:
        - /opt/redmine/{{ pillar['redmine']['domain'] }}/config/configuration.yml:/usr/src/redmine/config/configuration.yml:rw
        - /opt/redmine/{{ pillar['redmine']['domain'] }}/files:/usr/src/redmine/files:rw
    - watch:
        - file: /opt/redmine/{{ pillar['redmine']['domain'] }}/config/configuration.yml
    - environment:
      {%- if pillar['redmine']['environment']['tz'] is defined and pillar['redmine']['environment']['tz'] is not none %}
        - TZ: {{ pillar['redmine']['environment']['tz'] }}
      {%- else %}
        - TZ: 'Europe/Kiev'
      {%- endif %}

      {%- if pillar['redmine']['environment']['redmine_db_postgres'] is defined and pillar['redmine']['environment']['redmine_db_postgres'] is not none %}
        - REDMINE_DB_POSTGRES: {{ pillar['redmine']['environment']['redmine_db_postgres'] }}
      {%- endif %}
      {%- if pillar['redmine']['environment']['redmine_db_mysql'] is defined and pillar['redmine']['environment']['redmine_db_mysql'] is not none %}
        - REDMINE_DB_MYSQL: {{ pillar['redmine']['environment']['redmine_db_mysql'] }}
      {%- endif %}
        - REDMINE_DB_PORT: {{ pillar['redmine']['environment']['redmine_db_port'] }}
        - REDMINE_DB_DATABASE: {{ pillar['redmine']['environment']['redmine_db_database'] }}
        - REDMINE_DB_USERNAME: {{ pillar['redmine']['environment']['redmine_db_username'] }}
        - REDMINE_DB_PASSWORD: {{ pillar['redmine']['environment']['redmine_db_password'] }}
      {%- if pillar['redmine']['environment']['redmine_db_encoding'] is defined and pillar['redmine']['environment']['redmine_db_encoding'] is not none %}
        - REDMINE_DB_ENCODING: {{ pillar['redmine']['environment']['redmine_db_encoding'] }}
      {%- endif %}
      {%- if pillar['redmine']['environment']['redmine_no_db_migrate'] is defined and pillar['redmine']['environment']['redmine_no_db_migrate'] is not none %}
        - REDMINE_NO_DB_MIGRATE: {{ pillar['redmine']['environment']['redmine_no_db_migrate'] }}
      {%- endif %}
      {%- if pillar['redmine']['environment']['redmine_plugins_migrate'] is defined and pillar['redmine']['environment']['redmine_plugins_migrate'] is not none %}
        - REDMINE_PLUGINS_MIGRATE: {{ pillar['redmine']['environment']['redmine_plugins_migrate'] }}
      {%- endif %}
      {%- if pillar['redmine']['environment']['redmine_secret_key_base'] is defined and pillar['redmine']['environment']['redmine_secret_key_base'] is not none %}
        - REDMINE_SECRET_KEY_BASE: {{ pillar['redmine']['environment']['redmine_secret_key_base'] }}
      {%- endif %}
{# END docker section #}


{# ### START acme.sh setup section #}
clone_acme_sh:
  git.latest:
    - name: https://github.com/Neilpang/acme.sh.git
    - target: /opt/acme/git
    - force_reset: True
    - force_fetch: True

create_acme_home_dir:
  file.directory:
    - name: /opt/acme/home
    - makedirs: True
      
create_acme_cert_dir:
  file.directory:
    - name: /opt/acme/cert
    - makedirs: True
      
create_acme_config_dir:
  file.directory:
    - name: /opt/acme/config
    - makedirs: True

setup_acme_sh:
  cmd.run:
    - name: '/opt/acme/git/acme.sh --home /opt/acme/home --cert-home /opt/acme/cert --config-home /opt/acme/config --install'
    - runas: root
    - cwd: /opt/acme/git

create_acme_local:
  file.managed:
    - name: '/opt/acme/home/acme_local.sh'
    - mode: 0700
    - contents: |
        #!/bin/bash
        /opt/acme/home/acme.sh --home /opt/acme/home --cert-home /opt/acme/cert --config-home /opt/acme/config -w /opt/redmine/{{ pillar['redmine']['domain'] }}  "$@"
{# ### END acme.sh setup section #}


{# ### START nginx setup & config section #}

{# additional servernames #}
{%- if pillar['redmine']['aliases'] is defined and pillar['redmine']['aliases'] is not none %}
  {%- set aliases = pillar['redmine']['aliases'] %}
{%- else %}
  {%- set aliases = "" %}
{%- endif %}

{# add --force or --staging (or both) for renewal on condition #}
{%- if pillar['acme_force_renewal'] is defined and pillar['acme_force_renewal'] is not none %}
  {%- set acme_force_renewal = "--force" %}
{%- else %}
  {%- set acme_force_renewal = "" %}
{%- endif %}

{%- if pillar['acme_staging'] is defined and pillar['acme_staging'] is not none %}
  {%- set acme_staging = "--staging" %}
{%- else %}
  {%- set acme_staging = " " %}
{%- endif %}

{# additional nginx configuration #}
{%- set nginx_to_block_server = "" %}
{%- set nginx_to_location_slash = "" %}

{%- if pillar['redmine']['nginx_to_block_server'] is defined and pillar['redmine']['nginx_to_block_server'] is not none %}
  {%- set nginx_to_block_server = pillar['redmine']['nginx_to_block_server'] %}
{%- endif %}

{%- if pillar['redmine']['nginx_to_location_slash'] is defined and pillar['redmine']['nginx_to_location_slash'] is not none %}
  {%- set nginx_to_location_slash = pillar['redmine']['nginx_to_location_slash'] %}
{%- endif %}

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx

nginx_enabled:
  service.running:
    - name: nginx
    - enable: true

nginx_reload_cron:
  cron.present:
    - name: /usr/sbin/service nginx configtest && /usr/sbin/service nginx reload
    - identifier: nginx_reload
    - user: root
    - minute: 15
    - hour: 6

nginx_delete_default:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

redmine_ssl_dir:
  file.directory:
    - name: /opt/redmine/{{ pillar['redmine']['domain'] }}
    - mode: 755
    - makedirs: True

{# create nginx config without https for cert generation #}
nginx_main_config_managed_1:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - contents: |
        worker_processes 4;
        worker_rlimit_nofile 40000;
        events {
            worker_connections 8192;
        }
        http {
            server {
                listen 80;
                server_name _ ;
                location /.well-known/acme-challenge/ {
                    root  /opt/redmine/{{ pillar['redmine']['domain'] }}/;
                }
                location / {
                    return 301 https://$host$request_uri;
                }
            }
        }


nginx_reload_1:
  cmd.run:
    - runas: root
    - name: nginx -t && nginx -s reload


{% if acme_force_renewal %}

{# generate ssl cert at will forcelly #}
nginx_cert_force:
  cmd.run:
    - shell: /bin/bash
    - name: '/opt/acme/home/acme_local.sh --cert-file /opt/acme/cert/redmine_{{ pillar['redmine']['domain'] }}_cert.cer --key-file /opt/acme/cert/redmine_{{ pillar['redmine']['domain'] }}_key.key --ca-file /opt/acme/cert/redmine_{{ pillar['redmine']['domain'] }}_ca.cer --fullchain-file /opt/acme/cert/redmine_{{ pillar['redmine']['domain'] }}_fullchain.cer --issue -d {{ pillar['redmine']['domain'] }} {% for alias in aliases %} -d {{ alias }} {% endfor %} {{ acme_staging }}'

{% else %}

{# generate ssl cert once if no --force (acme_force_renewal pillar) is set #}
nginx_cert:
  cmd.run:
    - shell: /bin/bash
    - name: 'openssl verify -CAfile /opt/acme/cert/redmine_{{ pillar['redmine']['domain'] }}_ca.cer /opt/acme/cert/redmine_{{ pillar['redmine']['domain'] }}_fullchain.cer 2>&1 | grep -q -i -e "error\|cannot"; [ ${PIPESTATUS[1]} -eq 0 ] && /opt/acme/home/acme_local.sh --cert-file /opt/acme/cert/redmine_{{ pillar['redmine']['domain'] }}_cert.cer --key-file /opt/acme/cert/redmine_{{ pillar['redmine']['domain'] }}_key.key --ca-file /opt/acme/cert/redmine_{{ pillar['redmine']['domain'] }}_ca.cer --fullchain-file /opt/acme/cert/redmine_{{ pillar['redmine']['domain'] }}_fullchain.cer --issue -d {{ pillar['redmine']['domain'] }} {% for alias in aliases %} -d {{ alias }} {% endfor %} {{ acme_staging }}'

{% endif %}

{# check whether cert file exists #}
ssl_cert_chain_exists:
  file.exists:
    - name: /opt/acme/cert/redmine_{{ pillar['redmine']['domain'] }}_fullchain.cer
ssl_cert_key_exists:
  file.exists:
    - name: /opt/acme/cert/redmine_{{ pillar['redmine']['domain'] }}_key.key

nginx_main_config_managed_2:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - require:
        - ssl_cert_chain_exists
        - ssl_cert_key_exists
    - contents: |
        worker_processes 4;
        worker_rlimit_nofile 40000;
        events {
            worker_connections 8192;
        }
        http {
            server {
                listen 80;
                server_name _ ;
                location /.well-known/acme-challenge/ {
                    root  /opt/redmine/{{ pillar['redmine']['domain'] }}/;
                }
                location / {
                    return 301 https://$host$request_uri;
                }
            }
            server {
                listen 443 ssl;
                server_name {{ pillar['redmine']['domain'] }} {% for alias in aliases %} {{ alias }} {% endfor %};
                root  /opt/redmine/{{ pillar['redmine']['domain'] }}/;
                location /.well-known/acme-challenge/ {
                    root  /opt/redmine/{{ pillar['redmine']['domain'] }}/;
                }
                {{ nginx_to_block_server | indent(20) }}

                index index.html;
                ssl_certificate /opt/acme/cert/redmine_{{ pillar['redmine']['domain'] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/redmine_{{ pillar['redmine']['domain'] }}_key.key;
                location / {
                    proxy_pass http://localhost:3000/;
                    {{ nginx_to_location_slash | indent(20) }}
                }
            }
        }
      
nginx_reload_2:
  cmd.run:
    - runas: root
    - name: nginx -t && nginx -s reload
    - require:
        - nginx_main_config_managed_2

{# ### END nginx setup & config section #}

{% endif %}
