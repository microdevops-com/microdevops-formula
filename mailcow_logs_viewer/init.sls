{#- mailcow_logs_viewer/init.sls

  Deploys mailcow-logs-viewer: one isolated stack (app + PostgreSQL) per
  mailcow server, all fronted by a single nginx with one wildcard
  certificate issued through microdevops-formula/acme.

  Host requirements: docker with the compose plugin, nginx.
  Both are expected to be provided by other states.

  NOTE. The verify_and_issue macro ends with a whitespace-stripping
  endmacro tag, so its output carries no trailing newline. Therefore
  right-stripping Jinja comments must NOT be used between YAML blocks
  here: they would glue adjacent states onto one line. Everything below
  uses plain YAML comments instead.
-#}
{%- from 'mailcow_logs_viewer/map.jinja' import
      base, compose, image, db_image, instances, env_defaults,
      manage_nginx, manage_ws_map, http2_on, ssl_params, security_opt, snhbs,
      nginx_sls, nginx_pkg, nginx_req, remove_default_site,
      acme_account, acme_app, acme_domain, acme_domains, acme_reload,
      acme_state_id, acme_conf_glob, tls with context %}
{%- if instances %}
{%- from 'acme/macros.jinja' import verify_and_issue with context %}
{%- if manage_nginx and nginx_sls %}

include:
  - {{ nginx_sls }}
{%- endif %}

################################################################
# 1. Certificate
################################################################
# Issuance is idempotent: acme.sh returns exit code 2 when renewal is
# not due yet, and the macro counts 2 as success.

{{ verify_and_issue(acme_account, acme_app, acme_domains) }}

# verify_and_issue.sh does not pass --reloadcmd, so after the nightly
# renewal nginx would keep serving the old certificate from memory.
# Store the reloadcmd in the domain conf separately; the cron job picks
# it up from there. The unless is required because --install-cert fires
# the reload command on every invocation.
mlv-acme-reloadcmd:
  cmd.run:
    - shell: /bin/bash
    - name: >-
        /opt/acme/{{ acme_account }}/home/acme_local.sh --install-cert -d {{ acme_domain }}
        --cert-file '{{ tls.cert }}'
        --key-file '{{ tls.key }}'
        --ca-file '{{ tls.ca }}'
        --fullchain-file '{{ tls.fullchain }}'
        --reloadcmd '{{ acme_reload }}'
    - unless: grep -qs '^Le_ReloadCmd=' {{ acme_conf_glob }}
    - require:
      - cmd: {{ acme_state_id }}

################################################################
# 2. Shared scaffolding
################################################################

mlv-base-dir:
  file.directory:
    - name: {{ base }}
    - user: root
    - group: root
    - mode: '0750'
    - makedirs: True

mlv-unit:
  file.managed:
    - name: /etc/systemd/system/mailcow-logs-viewer@.service
    - source: salt://mailcow_logs_viewer/files/unit.service.jinja
    - template: jinja
    - mode: '0644'
    - context:
        base: {{ base }}
        compose: {{ compose }}

mlv-daemon-reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: mlv-unit
{%- if manage_nginx %}

{%- if not nginx_sls and nginx_pkg %}
mlv-nginx-pkg:
  pkg.installed:
    - name: nginx
{%- endif %}
{%- if remove_default_site %}

# The distro package ships a default_server vhost that answers every
# unknown Host. microdevops-formula/nginx removes it as well, so this
# state is a no-op when that formula is in play.
mlv-nginx-default-site:
  file.absent:
    - name: /etc/nginx/sites-enabled/default
{%- for k, v in nginx_req %}
    - require:
      - {{ k }}: {{ v }}
{%- endfor %}
    - onchanges_in:
      - cmd: mlv-nginx-configtest
{%- endif %}

# microdevops-formula/nginx declares its own service.running for nginx
# under the ID nginx_enable, but without reload: True. A second state on
# the same service is harmless and is what carries the graceful reload on
# config changes here.
mlv-nginx-service:
  service.running:
    - name: nginx
    - enable: True
    - reload: True
{%- for k, v in nginx_req %}
    - require:
      - {{ k }}: {{ v }}
{%- endfor %}

# Gate: no reload happens unless nginx -t passes first. A broken config
# does not kill nginx on SIGHUP - the master silently rolls back to the
# old one and keeps serving the old certificate, so without this check
# the failure would be silent.
mlv-nginx-configtest:
  cmd.run:
    - name: /usr/sbin/nginx -t
{%- for k, v in nginx_req %}
    - require:
      - {{ k }}: {{ v }}
{%- endfor %}
    - require_in:
      - service: mlv-nginx-service
{%- if snhbs %}

# Long viewer FQDNs overflow the default server_names_hash bucket and take
# the whole nginx config down with them. See map.jinja for the arithmetic.
mlv-nginx-server-names-hash:
  file.managed:
    - name: /etc/nginx/conf.d/server_names_hash.conf
    - mode: '0644'
    - makedirs: True
{%- for k, v in nginx_req %}
    - require:
      - {{ k }}: {{ v }}
{%- endfor %}
    - contents: |
        # Managed by Salt (mailcow_logs_viewer). Manual edits will be overwritten.
        server_names_hash_bucket_size {{ snhbs }};
    - onchanges_in:
      - cmd: mlv-nginx-configtest
    - watch_in:
      - service: mlv-nginx-service
{%- endif %}
{%- if manage_ws_map %}

# Required for the WebSocket stream on the Logs page. Set
# manage_ws_map: false if this map is already declared by another
# formula - a duplicate breaks nginx -t.
mlv-nginx-ws-map:
  file.managed:
    - name: /etc/nginx/conf.d/websocket_upgrade.conf
    - mode: '0644'
    - makedirs: True
{%- for k, v in nginx_req %}
    - require:
      - {{ k }}: {{ v }}
{%- endfor %}
    - contents: |
        # Managed by Salt (mailcow_logs_viewer). Manual edits will be overwritten.
        map $http_upgrade $connection_upgrade {
            default upgrade;
            ''      close;
        }
    - onchanges_in:
      - cmd: mlv-nginx-configtest
    - watch_in:
      - service: mlv-nginx-service
{%- endif %}
{%- endif %}

################################################################
# 3. Instances
################################################################
{%- for id, inst in instances.items() %}

mlv-dir-{{ id }}:
  file.directory:
    - name: {{ base }}/{{ id }}
    - user: root
    - group: root
    - mode: '0750'
    - require:
      - file: mlv-base-dir

mlv-env-{{ id }}:
  file.managed:
    - name: {{ base }}/{{ id }}/.env
    - source: salt://mailcow_logs_viewer/files/env.jinja
    - template: jinja
    - mode: '0600'
    - show_changes: False
    - context:
        id: {{ id }}
        inst: {{ inst | tojson }}
        env_defaults: {{ env_defaults | tojson }}
    - require:
      - file: mlv-dir-{{ id }}

mlv-compose-{{ id }}:
  file.managed:
    - name: {{ base }}/{{ id }}/docker-compose.yml
    - source: salt://mailcow_logs_viewer/files/docker-compose.yml.jinja
    - template: jinja
    - mode: '0640'
    - context:
        id: {{ id }}
        inst: {{ inst | tojson }}
        image: {{ image }}
        db_image: {{ db_image }}
        security_opt: {{ security_opt | tojson }}
    - require:
      - file: mlv-dir-{{ id }}

# The unit owns boot persistence and the very first start.
mlv-service-{{ id }}:
  service.running:
    - name: mailcow-logs-viewer@{{ id }}
    - enable: True
    - require:
      - cmd: mlv-daemon-reload
      - file: mlv-env-{{ id }}
      - file: mlv-compose-{{ id }}

# Changes to .env or docker-compose.yml are applied without a stop/start:
# up -d recreates only what actually changed.
mlv-apply-{{ id }}:
  cmd.run:
    - name: {{ compose }} up -d --remove-orphans
    - cwd: {{ base }}/{{ id }}
    - onchanges:
      - file: mlv-env-{{ id }}
      - file: mlv-compose-{{ id }}
    - require:
      - service: mlv-service-{{ id }}
{%- if manage_nginx %}

mlv-vhost-{{ id }}:
  file.managed:
    - name: /etc/nginx/sites-enabled/{{ inst.fqdn }}.conf
    - source: salt://mailcow_logs_viewer/files/vhost.conf.jinja
    - template: jinja
    - mode: '0644'
    - makedirs: True
    - context:
        fqdn: {{ inst.fqdn }}
        port: {{ inst.port }}
        http2_on: {{ http2_on }}
        ssl_params: {{ ssl_params }}
        tls: {{ tls | tojson }}
    - require:
{%- for k, v in nginx_req %}
      - {{ k }}: {{ v }}
{%- endfor %}
      - cmd: mlv-acme-reloadcmd
    - onchanges_in:
      - cmd: mlv-nginx-configtest
    - watch_in:
      - service: mlv-nginx-service
{%- endif %}
{%- endfor %}
{%- else %}

# pillar mailcow_logs_viewer:instances is empty - nothing to do.
{%- endif %}

