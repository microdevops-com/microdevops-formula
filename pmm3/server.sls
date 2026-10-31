{#-
  PMM 3 server in Docker: pmm-server + grafana-image-renderer on a dedicated docker network.
  Host layout (pmm3:path, default /opt/pmm3/<name>):
    srv/                                  - /srv of the container (all PMM data), owned by uid 1000 gid 0
    provisioning/dashboards-salt.yml      - Grafana dashboards provider for pmm3.alerting, mounted as a single file:
                                            dashboard provisioning of PMM lives in the image only
    cert-sync.sh                          - copies the acme certificate into srv/nginx and reloads nginx
  Grafana root_url is https://%(domain)s/graph - GF_SERVER_DOMAIN is always set to pmm3:name,
  otherwise links in alert notifications point to localhost.
-#}
{%- if pillar['pmm3'] is defined %}
{%- from 'pmm3/map.jinja' import pmm3 with context %}
{%- from 'acme/macros.jinja' import verify_and_issue %}
{%- set server_url = pmm3['api_url'].rsplit('/graph', 1)[0] %}
{%- set environment = {
  'PMM_ENABLE_UPDATES': 'false',
  'GF_SERVER_DOMAIN': pmm3['name'],
  'GF_RENDERING_SERVER_URL': 'http://renderer:8081/render',
  'GF_RENDERING_CALLBACK_URL': 'https://pmm-server:8443/graph/',
} %}
{%- do environment.update(pmm3['env_vars']) %}

pmm3_network:
  docker_network.present:
    - name: {{ pmm3['network'] }}

{#- containers removed before pmm3-server starts, e.g. a previous server holding port 443 #}
{%- for container in pmm3.get('replaces', []) %}

pmm3_replaces_{{ container }}:
  docker_container.absent:
    - name: {{ container }}
    - force: True
    - require_in:
      - docker_container: pmm3_server_container
{%- endfor %}

pmm3_dirs:
  file.directory:
    - names:
      - {{ pmm3['path'] }}
      - {{ pmm3['provisioning_path'] }}
    - mode: 755
    - makedirs: True

{#- PMM runs as uid 1000 gid 0 and initializes an empty /srv on the first start #}
pmm3_srv_dir:
  file.directory:
    - name: {{ pmm3['srv_path'] }}
    - user: {{ pmm3['srv_user'] }}
    - group: {{ pmm3['srv_group'] }}
    - mode: 755
    - makedirs: True

{#- must exist before the container starts, otherwise docker creates a directory in its place #}
pmm3_dashboards_provider:
  file.serialize:
    - name: {{ pmm3['provisioning_path'] }}/dashboards-salt.yml
    - mode: 644
    - formatter: yaml
    - require:
      - file: pmm3_dirs
    - dataset:
        apiVersion: 1
        providers:
          - name: salt_dashboards
            orgId: 1
            type: file
            disableDeletion: False
            allowUiUpdates: False
            updateIntervalSeconds: 30
            options:
              path: /srv/grafana/dashboards
              foldersFromFilesStructure: True

pmm3_renderer_container:
  cmd.run:
    - name: docker pull {{ pmm3['renderer']['image'] }}
    - unless: docker image inspect {{ pmm3['renderer']['image'] }} > /dev/null
  docker_container.running:
    - name: pmm3-renderer
    - image: {{ pmm3['renderer']['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - environment:
      {#- renderer v5 ignores IGNORE_HTTPS_ERRORS; the callback certificate is not issued for pmm-server #}
      - BROWSER_FLAG: --ignore-certificate-errors
    - networks:
      - {{ pmm3['network'] }}:
        - aliases:
          - renderer
    - require:
      - cmd: pmm3_renderer_container
      - docker_network: pmm3_network

pmm3_server_container:
  cmd.run:
    - name: docker pull {{ pmm3['image'] }}
    - unless: docker image inspect {{ pmm3['image'] }} > /dev/null
  docker_container.running:
    - name: pmm3-server
    - image: {{ pmm3['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish: {{ pmm3['publish'] | json }}
    - binds:
      - {{ pmm3['srv_path'] }}:/srv
      - {{ pmm3['provisioning_path'] }}/dashboards-salt.yml:/usr/share/grafana/conf/provisioning/dashboards/salt.yml:ro
    - networks:
      - {{ pmm3['network'] }}:
        - aliases:
          - pmm-server
    - environment:
      {%- for key, value in environment | dictsort %}
      - {{ key }}: {{ ('true' if value is sameas true else 'false' if value is sameas false else value | string) | json }}
      {%- endfor %}
    - require:
      - cmd: pmm3_server_container
      - docker_network: pmm3_network
      - file: pmm3_srv_dir
      - docker_container: pmm3_renderer_container
    - watch:
      {#- the provider file is bind-mounted by inode: a rewritten file is only seen by a new container #}
      - file: pmm3_dashboards_provider

pmm3_server_ready:
  cmd.run:
    - name: timeout 600 sh -c 'until curl -sfk -o /dev/null {{ server_url }}/v1/server/readyz; do sleep 5; done'
    - unless: curl -sfk -o /dev/null {{ server_url }}/v1/server/readyz
    - require:
      - docker_container: pmm3_server_container

pmm3_admin_password:
  cmd.run:
    - name: docker exec pmm3-server change-admin-password "$PMM_PASSWORD"
    - unless: curl -sfk -o /dev/null -u "admin:$PMM_PASSWORD" {{ pmm3['api_url'] }}/api/user
    - env:
      - PMM_PASSWORD: {{ pmm3['admin_password'] | json }}
    - require:
      - cmd: pmm3_server_ready
{%- if pmm3.get('acme_account') %}

{{ verify_and_issue(pmm3['acme_account'], 'pmm3', pmm3['name']) }}

{#- PMM uses /srv/nginx/certificate.{crt,key} and never regenerates existing files #}
pmm3_cert_sync_script:
  file.managed:
    - name: {{ pmm3['path'] }}/cert-sync.sh
    - mode: 700
    - contents: |
        #!/bin/bash
        # Copy the acme certificate into PMM's /srv/nginx, reload nginx if it changed
        set -euo pipefail
        src=/opt/acme/cert/pmm3_{{ pmm3['name'] }}
        dst={{ pmm3['srv_path'] }}/nginx
        changed=0
        for pair in fullchain.cer:certificate.crt:644 key.key:certificate.key:600; do
          IFS=: read -r from to mode <<< "$pair"
          if ! cmp -s "${src}_${from}" "${dst}/${to}"; then
            install -D -o {{ pmm3['srv_user'] }} -g {{ pmm3['srv_group'] }} -m "$mode" "${src}_${from}" "${dst}/${to}"
            changed=1
          fi
        done
        if [ "$changed" = 1 ] && [ "$(docker inspect -f '{{ '{{' }}.State.Running{{ '}}' }}' pmm3-server 2>/dev/null)" = true ]; then
          docker exec pmm3-server nginx -s reload
        fi

pmm3_cert_sync:
  cmd.run:
    - name: {{ pmm3['path'] }}/cert-sync.sh
    - unless: >-
        cmp -s /opt/acme/cert/pmm3_{{ pmm3['name'] }}_fullchain.cer {{ pmm3['srv_path'] }}/nginx/certificate.crt &&
        cmp -s /opt/acme/cert/pmm3_{{ pmm3['name'] }}_key.key {{ pmm3['srv_path'] }}/nginx/certificate.key
    - require:
      - file: pmm3_cert_sync_script
      - cmd: pmm3_server_ready

{#- acme.sh renews by its own cron, this one delivers the renewed certificate #}
pmm3_cert_sync_cron:
  cron.present:
    - name: {{ pmm3['path'] }}/cert-sync.sh
    - identifier: pmm3_cert_sync
    - user: root
    - minute: 20
    - hour: 6
{%- endif %}
{%- endif %}
