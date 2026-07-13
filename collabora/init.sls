{% if pillar["collabora"] is defined and pillar["acme"] is defined %}
{% set acme = pillar['acme'].keys() | first %}

  {% from "acme/macros.jinja" import verify_and_issue %}

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx
  {%- if pillar["collabora"]["nginx_sites_enabled"] | default(false) %}
create nginx.conf:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - contents: |
        #user www-data;
        worker_processes auto;
        worker_rlimit_nofile 40000;
        pid /run/nginx.pid;
        include /etc/nginx/modules-enabled/*.conf;
        events {
            worker_connections 8192;
        }
        http {
          sendfile on;
          tcp_nopush on;
          tcp_nodelay on;
          keepalive_timeout 65;
          types_hash_max_size 2048;
          server_names_hash_bucket_size 64;
          include /etc/nginx/mime.types;
          default_type application/octet-stream;
          ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
          ssl_prefer_server_ciphers on;
          access_log /var/log/nginx/access.log;
          error_log /var/log/nginx/error.log;
          gzip on;
          include /etc/nginx/conf.d/*.conf;
          include /etc/nginx/sites-enabled/*;
        }
    {% if pillar["collabora"]["full"] | default(false) %}
create /etc/nginx/sites-available/{{ pillar["collabora"]["name"] }}.conf:
  file.managed:
    - name: /etc/nginx/sites-available/{{ pillar["collabora"]["name"] }}.conf
    - contents: |
        {%- if pillar["collabora"]["external_port"] is not defined %}
        server {
          listen 80;
          server_name {{ pillar["collabora"]["name"] }};
          return 301 https://$host$request_uri;
        }
        {%- endif %}
        upstream {{ pillar["collabora"]["name"] | replace(".","_") }} {
          server 127.0.0.1:{{ pillar["collabora"]["internal_port"] | default('9980') }};
        }
        server {
          listen 443 ssl;
          server_name {{ pillar["collabora"]["name"] }};
          ssl_certificate /opt/acme/cert/collabora_{{ pillar["collabora"]["name"] }}_fullchain.cer;
          ssl_certificate_key /opt/acme/cert/collabora_{{ pillar["collabora"]["name"] }}_key.key;
          # static files
          location ^~ /browser {
            proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
            proxy_set_header Host $http_host;
          }
          # WOPI discovery URL
          location ^~ /hosting/discovery {
            proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
            proxy_set_header Host $http_host;
          }
          # Capabilities
          location ^~ /hosting/capabilities {
            proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
            proxy_set_header Host $http_host;
          }
          # main websocket
          location ~ ^/cool/(.*)/ws$ {
            proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "Upgrade";
            proxy_set_header Host $http_host;
            proxy_read_timeout 36000s;
          }
          # download, presentation and image upload
          location ~ ^/(c|l)ool {
            proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
            proxy_set_header Host $http_host;
          }
          # Admin Console websocket
          location ^~ /cool/adminws {
            proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "Upgrade";
            proxy_set_header Host $http_host;
            proxy_read_timeout 36000s;
          }
        }

create symlink /etc/nginx/sites-enabled/{{ pillar["collabora"]["name"] }}.conf:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ pillar["collabora"]["name"] }}.conf
    - target: /etc/nginx/sites-available/{{ pillar["collabora"]["name"] }}.conf
    - force: True

    {% else %}

      {%- for domain in pillar["collabora"]["domains"] %}
create /etc/nginx/sites-available/{{ domain["name"] }}.conf:
  file.managed:
    - name: /etc/nginx/sites-available/{{ domain["name"] }}.conf
    - contents: |
        {%- if pillar["collabora"]["external_port"] is not defined %}
        server {
          listen 80;
          server_name {{ domain["name"] }};
          return 301 https://$host$request_uri;
        }
        {%- endif %}
        upstream {{ domain["name"] | replace(".","_") }} {
          server 127.0.0.1:{{ domain["internal_port"] | default('9980') }};
        }
        server {
          listen 443 ssl;
          server_name {{ domain["name"] }};
          ssl_certificate /opt/acme/cert/collabora_{{ domain["name"] }}_fullchain.cer;
          ssl_certificate_key /opt/acme/cert/collabora_{{ domain["name"] }}_key.key;
          # static files
          location ^~ /browser {
            proxy_pass http://{{ domain["name"] | replace(".","_") }};
            proxy_set_header Host $http_host;
          }
          # WOPI discovery URL
          location ^~ /hosting/discovery {
            proxy_pass http://{{ domain["name"] | replace(".","_") }};
            proxy_set_header Host $http_host;
          }
          # Capabilities
          location ^~ /hosting/capabilities {
            proxy_pass http://{{ domain["name"] | replace(".","_") }};
            proxy_set_header Host $http_host;
          }
          # main websocket
          location ~ ^/cool/(.*)/ws$ {
            proxy_pass http://{{ domain["name"] | replace(".","_") }};
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "Upgrade";
            proxy_set_header Host $http_host;
            proxy_read_timeout 36000s;
          }
          # download, presentation and image upload
          location ~ ^/(c|l)ool {
            proxy_pass http://{{ domain["name"] | replace(".","_") }};
            proxy_set_header Host $http_host;
          }
          # Admin Console websocket
          location ^~ /cool/adminws {
            proxy_pass http://{{ domain["name"] | replace(".","_") }};
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "Upgrade";
            proxy_set_header Host $http_host;
            proxy_read_timeout 36000s;
          }
        }

create symlink /etc/nginx/sites-enabled/{{ domain["name"] }}.conf:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ domain["name"] }}.conf
    - target: /etc/nginx/sites-available/{{ domain["name"] }}.conf
    - force: True
      {%- endfor %}

    {%- endif %}

  {%- else %}

nginx_files_1:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - contents: |
        worker_processes 4;
        worker_rlimit_nofile 40000;
        events {
          worker_connections 8192;
        }
        http {
          include /etc/nginx/mime.types;
          default_type application/octet-stream;
          sendfile on;
          keepalive_timeout 65;
            server {
              listen 80;
              return 301 https://$host$request_uri;
            }
    {% if pillar["collabora"]["full"] | default(false) %}
            upstream {{ pillar["collabora"]["name"] | replace(".","_") }} {
              server 127.0.0.1:{{ pillar["collabora"]["internal_port"] | default('9980') }};
            }
            server {
              listen 443 ssl;
              server_name {{ pillar["collabora"]["name"] }};
              ssl_certificate /opt/acme/cert/collabora_{{ pillar["collabora"]["name"] }}_fullchain.cer;
              ssl_certificate_key /opt/acme/cert/collabora_{{ pillar["collabora"]["name"] }}_key.key;
              # static files
              location ^~ /browser {
               proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
               proxy_set_header Host $http_host;
              }
              # WOPI discovery URL
              location ^~ /hosting/discovery {
               proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
               proxy_set_header Host $http_host;
              }
              # Capabilities
              location ^~ /hosting/capabilities {
               proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
               proxy_set_header Host $http_host;
              }
              # main websocket
              location ~ ^/cool/(.*)/ws$ {
               proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
               proxy_set_header Upgrade $http_upgrade;
               proxy_set_header Connection "Upgrade";
               proxy_set_header Host $http_host;
               proxy_read_timeout 36000s;
              }
              # download, presentation and image upload
              location ~ ^/(c|l)ool {
               proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
               proxy_set_header Host $http_host;
              }
              # Admin Console websocket
              location ^~ /cool/adminws {
               proxy_pass http://{{ pillar["collabora"]["name"] | replace(".","_") }};
               proxy_set_header Upgrade $http_upgrade;
               proxy_set_header Connection "Upgrade";
               proxy_set_header Host $http_host;
               proxy_read_timeout 36000s;
              }
            }
    {% else %}
      {%- for domain in pillar["collabora"]["domains"] %}
            upstream {{ domain["name"] | replace(".","_") }} {
              server 127.0.0.1:{{ domain["internal_port"] | default('9980') }};
            }
            server {
              listen 443 ssl;
              server_name {{ domain["name"] }};
              ssl_certificate /opt/acme/cert/collabora_{{ domain["name"] }}_fullchain.cer;
              ssl_certificate_key /opt/acme/cert/collabora_{{ domain["name"] }}_key.key;
              # static files
              location ^~ /browser {
               proxy_pass http://{{ domain["name"] | replace(".","_") }};
               proxy_set_header Host $http_host;
              }
              # WOPI discovery URL
              location ^~ /hosting/discovery {
               proxy_pass http://{{ domain["name"] | replace(".","_") }};
               proxy_set_header Host $http_host;
              }
              # Capabilities
              location ^~ /hosting/capabilities {
               proxy_pass http://{{ domain["name"] | replace(".","_") }};
               proxy_set_header Host $http_host;
              }
              # main websocket
              location ~ ^/cool/(.*)/ws$ {
               proxy_pass http://{{ domain["name"] | replace(".","_") }};
               proxy_set_header Upgrade $http_upgrade;
               proxy_set_header Connection "Upgrade";
               proxy_set_header Host $http_host;
               proxy_read_timeout 36000s;
              }
              # download, presentation and image upload
              location ~ ^/(c|l)ool {
               proxy_pass http://{{ domain["name"] | replace(".","_") }};
               proxy_set_header Host $http_host;
              }
              # Admin Console websocket
              location ^~ /cool/adminws {
               proxy_pass http://{{ domain["name"] | replace(".","_") }};
               proxy_set_header Upgrade $http_upgrade;
               proxy_set_header Connection "Upgrade";
               proxy_set_header Host $http_host;
               proxy_read_timeout 36000s;
              }
            }
      {%- endfor %}
    {%- endif %}
        }
  {%- endif %}
nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default


  {% if pillar["collabora"]["full"] | default(false) %}
    {#- Version handling: "24.04" tracks the latest of that major line;
        "24.04.18.3" (or "24.04.18.3-1") pins an exact package. The apt repo URI
        always uses the major line, derived from the first two components. -#}
    {%- set version = pillar["collabora"].get("version", "24.04") | string %}
    {%- set _vparts = version.split("-")[0].split(".") %}
    {%- set major = _vparts[:2] | join(".") %}
    {%- set is_exact = _vparts | length >= 3 %}
    {%- set pin = version if "-" in version else version ~ "-1" %}
    {#- nextcloud-office-brand uses a different version scheme than coolwsd
        (e.g. brand "25.04.10-3" vs coolwsd "25.04.10.3-1", and in 24.04 the
        brand is just "24.04-37"), so it can't be derived - pin it explicitly
        via `brand_version` if you need a reproducible/matching brand. -#}
    {%- set brand_version = pillar["collabora"].get("brand_version") %}
    {#- edition: "enterprise" (default) installs from the per-customer repo and
        requires customer_hash; "code" installs the free Collabora Online
        Development Edition from the public CODE-deb repo (no hash needed).
        The CODE repo is flat (no per-major path segment) and only carries the
        current major line, so with edition: code the `version` pin can only
        point at releases of that line. -#}
    {%- set edition = pillar["collabora"].get("edition", "enterprise") %}
    {%- if edition == "code" %}
      {%- set repo_uri = "https://www.collaboraoffice.com/repos/CollaboraOnline/CODE-deb" %}
      {%- set brand_package = pillar["collabora"].get("brand_package", "code-brand") %}
    {%- else %}
      {%- set repo_uri = "https://www.collaboraoffice.com/repos/CollaboraOnline/" ~ major ~ "/customer-deb-" ~ pillar["collabora"].get("customer_hash", "MISSING-CUSTOMER-HASH") %}
      {%- set brand_package = pillar["collabora"].get("brand_package", "nextcloud-office-brand") %}
    {%- endif %}
    {%- set cool = pillar["collabora"].get("coolwsd", {}) %}
    {%- set cool_admin = cool.get("admin", {}) %}
    {%- set cool_overrides = cool.get("overrides", {}) %}
    {%- set cool_ag = cool.get("alias_groups", {}) %}
    {#- Base flags copied verbatim from the packaged coolwsd.service ExecStart
        (identical in 24.04 and 25.04). Everything appended after them are the
        pillar-driven runtime overrides, so /etc/coolwsd/coolwsd.xml is never
        templated and stays owned (and upgraded) by the package. -#}
    {%- set ns = namespace(o=[
        "--o:sys_template_path=/opt/cool/systemplate",
        "--o:child_root_path=/opt/cool/child-roots",
        "--o:file_server_root_path=/usr/share/coolwsd",
        "--o:cache_files.path=/opt/cool/cache"]) %}
    {%- for k, v in cool_overrides.items() %}
      {%- set _val = (v | string | lower) if v is boolean else (v | string) %}
      {%- set ns.o = ns.o + ["--o:" ~ k ~ "=" ~ _val] %}
    {%- endfor %}
    {%- if cool_ag %}
      {#- The [@mode] attribute overrides fine from the command line, but the
          group[] host list does NOT: coolwsd builds that list from the
          coolwsd.xml DOM and --o: cannot create the array nodes. So only mode
          goes here; the <group> hosts are written into coolwsd.xml (blockreplace
          state below). -#}
      {%- set ns.o = ns.o + ["--o:storage.wopi.alias_groups[@mode]=" ~ cool_ag.get("mode", "groups")] %}
    {%- endif %}

{%- if pillar["collabora"].get("coolwsd_xml") and not pillar["collabora"].get("coolwsd") %}
collabora_pillar_migration_required:
  test.fail_without_changes:
    - name: >-
        The 'coolwsd_xml' pillar block is obsolete. Migrate its values to the new
        'coolwsd' override block (admin / overrides / alias_groups) - see
        collabora/pillar.example.
    - failhard: True
{%- endif %}

{%- if edition != "code" and not pillar["collabora"].get("customer_hash") %}
collabora_customer_hash_required:
  test.fail_without_changes:
    - name: >-
        collabora:customer_hash is required for the enterprise edition. Either
        set it, or set 'edition: code' to install the free CODE build from the
        public CODE-deb repo.
    - failhard: True
{%- endif %}

    {{ verify_and_issue(acme, "collabora", pillar["collabora"]["name"]) }}

download_collaboraonline-release-keyring.gpg:
  file.managed:
    - name: /usr/share/keyrings/collaboraonline-release-keyring.gpg
    - source: https://collaboraoffice.com/downloads/gpg/collaboraonline-release-keyring.gpg
    - skip_verify: True

apt_sources_list.d_collabora.list:
  file.managed:
    - name: /etc/apt/sources.list.d/collaboraonline.sources
    - contents: |
        Types: deb
        URIs: {{ repo_uri }}
        Suites: ./
        Signed-By: /usr/share/keyrings/collaboraonline-release-keyring.gpg
    - require:
      - file: download_collaboraonline-release-keyring.gpg

apt_update:
  cmd.run:
    - name: apt update
    - require:
      - file: apt_sources_list.d_collabora.list

# coolwsd is pinned to an exact point release when `version` carries a patch
# component (e.g. "24.04.18.3"); with just a major line ("24.04") it tracks the
# latest release there. The brand package follows the repo unless brand_version
# pins it.
colabora_install:
{%- if is_exact %}
  pkg.installed:
    - name: coolwsd
    - version: '{{ pin }}'
{%- else %}
  pkg.latest:
    - name: coolwsd
{%- endif %}
    - require:
      - cmd: apt_update

colabora_install_brand:
{%- if brand_version %}
  pkg.installed:
    - name: {{ brand_package }}
    - version: '{{ brand_version }}'
{%- else %}
  pkg.latest:
    - name: {{ brand_package }}
{%- endif %}
    - require:
      - cmd: apt_update
      - pkg: colabora_install

# On a package upgrade dpkg keeps our modified coolwsd.xml and writes the new
# version's default alongside it as coolwsd.xml.dpkg-dist. Adopt that fresh
# default (content only, so the file's owner/mode are preserved), backing ours
# up first; the drop-in / admin password / WOPI groups below are then re-applied
# on top. This makes upgrades follow the new packaged config instead of freezing
# the old file. Steady-state applies find no .dpkg-dist and do nothing.
coolwsd_adopt_packaged_config:
  cmd.run:
    - name: |
        set -e
        cp -a /etc/coolwsd/coolwsd.xml /etc/coolwsd/coolwsd.xml.salt-bak
        cp -a /etc/coolwsd/coolwsd.xml /etc/coolwsd/coolwsd.xml.salt-tmp
        cat /etc/coolwsd/coolwsd.xml.dpkg-dist > /etc/coolwsd/coolwsd.xml.salt-tmp
        mv /etc/coolwsd/coolwsd.xml.salt-tmp /etc/coolwsd/coolwsd.xml
        rm -f /etc/coolwsd/coolwsd.xml.dpkg-dist
    - onlyif: test -f /etc/coolwsd/coolwsd.xml.dpkg-dist
    - require:
      - pkg: colabora_install

# Runtime overrides via a systemd drop-in. coolwsd.xml is NOT managed by Salt,
# so the package's version-correct default is always kept; our values are
# layered on top at launch with --o:, exactly like the Docker extra_params.
coolwsd_systemd_dropin:
  file.managed:
    - name: /etc/systemd/system/coolwsd.service.d/override.conf
    - makedirs: True
    - contents: |
        # Managed by Salt (collabora formula) - do not edit by hand.
        [Service]
        ExecStart=
        ExecStart=/usr/bin/coolwsd --version \
                  {{ ns.o | join(' \\\n                  ') }}
    - require:
      - pkg: colabora_install

coolwsd_daemon_reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: coolwsd_systemd_dropin
{%- if cool_admin.get("password") %}

# Admin console credentials via coolconfig (PBKDF2-hashed, not plaintext),
# re-applied only when they change (tracked by a salted-hash marker file).
coolwsd_admin_password_marker:
  file.managed:
    - name: /etc/coolwsd/.salt-admin-pw
    - mode: '0600'
    - makedirs: True
    - contents: {{ salt['hashutil.sha256_digest'](cool_admin.get("username", "admin") ~ ":" ~ cool_admin["password"]) }}
    - require:
      - pkg: colabora_install

coolwsd_set_admin_password:
  cmd.run:
    - name: >-
        coolconfig set-admin-password
        --user='{{ cool_admin.get("username", "admin") }}'
        --password='{{ cool_admin["password"] }}'
    - onchanges:
      - file: coolwsd_admin_password_marker
      - cmd: coolwsd_adopt_packaged_config
    - require:
      - pkg: colabora_install
      - cmd: coolwsd_adopt_packaged_config
{%- endif %}
{%- if cool_ag and cool_ag.get("groups") %}

# WOPI host list lives in coolwsd.xml (coolwsd can't take it from --o:). The
# <group> block is managed between markers, so re-applies are idempotent and the
# rest of the package's config file is left untouched.
coolwsd_alias_groups_hosts:
  file.blockreplace:
    - name: /etc/coolwsd/coolwsd.xml
    - marker_start: '<!-- SALT:wopi-alias-groups:start -->'
    - marker_end: '<!-- SALT:wopi-alias-groups:end -->'
    - insert_before_match: '</alias_groups>'
    - append_if_not_found: False
    - content: |
        {%- for host in cool_ag.get("groups", []) %}
        <group><host desc="hostname to allow or deny." allow="true">{{ host }}</host></group>
        {%- endfor %}
    - require:
      - pkg: colabora_install
      - cmd: coolwsd_adopt_packaged_config
{%- if cool_admin.get("password") %}
      - cmd: coolwsd_set_admin_password
{%- endif %}
{%- endif %}

collabora_systemd_service:
  service.running:
    - name: coolwsd
    - enable: True
    - require:
      - pkg: colabora_install
      - cmd: coolwsd_daemon_reload
    - watch:
      - file: coolwsd_systemd_dropin
      - cmd: coolwsd_adopt_packaged_config
{%- if cool_ag and cool_ag.get("groups") %}
      - file: coolwsd_alias_groups_hosts
{%- endif %}
{%- if cool_admin.get("password") %}
      - cmd: coolwsd_set_admin_password
{%- endif %}

  {% else %}

    {%- for domain in pillar["collabora"]["domains"] %}

    {%- if domain.get('acme_configs')|default([]) is defined %}
      {%- for acme_cfg in domain['acme_configs'] %}
        {% for acme_domain in acme_cfg["domains"] %}
          {{ verify_and_issue(acme_cfg["name"], "collabora", acme_domain) }}
        {%- endfor %}
      {%- endfor %}
    {%- else %}
        {{ verify_and_issue(acme, "collabora", domain["name"]) }}
    {%- endif %}

collabora_image_{{ loop.index }}:
  cmd.run:
    - name: docker pull {{ domain["image"] }}

collabora_container_{{ loop.index }}:
  docker_container.running:
    - name: collabora-{{ domain["name"] }}
    - user: cool
    - image: {{ domain["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - cap_add: MKNOD
    - privileged: True
    - publish:
        - 127.0.0.1:{{ domain["internal_port"] }}:9980/tcp
    - environment:
        - extra_params: --o:ssl.enable=false --o:ssl.termination=true
      {%- for var_key, var_val in domain["env_vars"].items() %}
        - {{ var_key }}: {{ var_val }}
      {%- endfor %}

    {%- endfor %}

  {%- endif %}

nginx_reload:
  cmd.run:
    - runas: root
    - name: service nginx configtest && service nginx reload

nginx_reload_cron:
  cron.present:
    - name: /usr/sbin/service nginx configtest && /usr/sbin/service nginx reload
    - identifier: nginx_reload
    - user: root
    - minute: 15
    - hour: 6

{% endif %}
