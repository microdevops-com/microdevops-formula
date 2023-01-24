{% if pillar["atlassian-servicedesk"] is defined %}
{% from 'atlassian-servicedesk/map.jinja' import servicedesk with context %}

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx

nginx_files_1:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - contents: |
        worker_processes 4;
        worker_rlimit_nofile 40000;
        events {
            worker_connections 8192;
            use epoll;
            multi_accept on;
        }
        http {
            include /etc/nginx/mime.types;
            default_type application/octet-stream;
            sendfile on;
            tcp_nopush on;
            tcp_nodelay on;
            gzip on;
            gzip_comp_level 4;
            gzip_types text/plain text/css application/x-javascript text/xml application/xml application/xml+rss text/javascript;
            gzip_vary on;
            gzip_proxied any;
            client_max_body_size 1000m;
  {%- if pillar["atlassian-servicedesk"]["nginx_forwards"] is defined %}
    {%- for domain in pillar["atlassian-servicedesk"]["nginx_forwards"] %}
            server {
                listen 443 ssl;
                server_name {{ domain }};
                ssl_certificate /opt/acme/cert/{{ domain }}/fullchain.cer;
                ssl_certificate_key /opt/acme/cert/{{ domain }}/{{ domain }}.key;
                return 301 https://{{ pillar["atlassian-servicedesk"]["http_proxyName"] }}$request_uri;
            }
    {%- endfor %}
  {%- endif %}
            server {
                listen 80;
                return 301 https://{{ pillar["atlassian-servicedesk"]["http_proxyName"] }}$request_uri;
            }
            server {
                listen 443 ssl;
                server_name {{ pillar["atlassian-servicedesk"]["http_proxyName"] }};
                ssl_certificate /opt/acme/cert/{{ pillar["atlassian-servicedesk"]["http_proxyName"] }}/fullchain.cer;
                ssl_certificate_key /opt/acme/cert/{{ pillar["atlassian-servicedesk"]["http_proxyName"] }}/{{ pillar["atlassian-servicedesk"]["http_proxyName"] }}.key;
                client_max_body_size 200M;
                client_body_buffer_size 128k;
                location / {
                    proxy_pass http://localhost:{{ pillar["atlassian-servicedesk"]["http_port"] }};
                    proxy_set_header X-Forwarded-Host $host;
                    proxy_set_header X-Forwarded-Server $host;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                }
            }
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- if pillar["atlassian-servicedesk"]["acme_configs"] is not defined %}
nginx_cert:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["atlassian-servicedesk"]["acme_account"] }}/verify_and_issue.sh atlassian-servicedesk {{ pillar["atlassian-servicedesk"]["http_proxyName"] }}"
  {%- else %}
    {% for acme_config in pillar["atlassian-servicedesk"]["acme_configs"] %}
nginx_cert_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ acme_config["name"] }}/verify_and_issue.sh atlassian-servicedesk {%- for domain in acme_config["domains"] %} {{ domain }} {% endfor -%}"
    {%- endfor%}
  {%- endif %}
nginx_reload:
  cmd.run:
    - runas: root
    - name: service nginx configtest && service nginx restart

nginx_reload_cron:
  cron.present:
    - name: /usr/sbin/service nginx configtest && /usr/sbin/service nginx restart
    - identifier: nginx_reload
    - user: root
    - minute: 15
    - hour: 6

servicedesk-dependencies:
  pkg.installed:
    - pkgs:
      - libxslt1.1
      - xsltproc
      - openjdk-11-jdk

servicedesk:
  file.managed:
    - name: /etc/systemd/system/atlassian-servicedesk.service
    - source: salt://atlassian-servicedesk/files/atlassian-servicedesk.service
    - template: jinja
    - defaults:
        config: {{ servicedesk|json }}

  module.wait:
    - name: service.systemctl_reload
    - watch:
      - file: servicedesk

  group.present:
    - name: {{ servicedesk.group }}

  user.present:
    - name: {{ servicedesk.user }}
    - home: {{ servicedesk.dirs.home }}
    - gid: {{ servicedesk.group }}
    - require:
      - group: servicedesk
      - file: servicedesk-dir

  service.running:
    - name: atlassian-servicedesk
    - enable: True
    - require:
      - file: servicedesk
  {%- if "addon" in pillar["atlassian-servicedesk"] %}
      - file: addon
    {%- if "javaopts" in pillar["atlassian-servicedesk"]["addon"] %}
      - file: addon-javaopts
addon-javaopts:
  file.replace:
    - name: '{{ pillar["atlassian-servicedesk"]["dir"] }}/scripts/env.sh'
    - pattern: '^ *export JAVA_OPTS=.*$'
    - repl: 'export JAVA_OPTS="{{ pillar["atlassian-servicedesk"]["addon"]["javaopts"] }} ${JAVA_OPTS}"'
    - append_if_not_found: True
    - require:
      - file: servicedesk-script-env.sh
    {%- endif %}
addon:
  file.managed:
    - name: {{ pillar["atlassian-servicedesk"]["addon"]["target"] }}
    - source: {{ pillar["atlassian-servicedesk"]["addon"]["source"] }}
    - require:
      - archive: servicedesk-install
  {%- endif %}

servicedesk-graceful-down:
  service.dead:
    - name: atlassian-servicedesk
    - require:
      - module: servicedesk
    - prereq:
      - file: servicedesk-install

servicedesk-install:
  archive.extracted:
    - name: {{ servicedesk.dirs.extract }}
    - source: {{ servicedesk.url }}
    - source_hash: {{ servicedesk.url_hash }}
    - options: z
    - if_missing: {{ servicedesk.dirs.current_install }}
    - keep: True
    - require:
      - file: servicedesk-extractdir

  file.symlink:
    - name: {{ servicedesk.dirs.install }}
    - target: {{ servicedesk.dirs.current_install }}
    - require:
      - archive: servicedesk-install
    - watch_in:
      - service: servicedesk

servicedesk-server-xsl:
  file.managed:
    - name: {{ servicedesk.dirs.temp }}/server.xsl
    - source: salt://atlassian-servicedesk/files/server.xsl
    - template: jinja
    - require:
      - file: servicedesk-temptdir

  cmd.run:
    - name: |
        xsltproc --stringparam pHttpPort "{{ servicedesk.get('http_port', '') }}" \
          --stringparam pHttpScheme "{{ servicedesk.get('http_scheme', '') }}" \
          --stringparam pHttpProxyName "{{ servicedesk.get('http_proxyName', '') }}" \
          --stringparam pHttpProxyPort "{{ servicedesk.get('http_proxyPort', '') }}" \
          --stringparam pAjpPort "{{ servicedesk.get('ajp_port', '') }}" \
          --stringparam pAccessLogFormat "{{ servicedesk.get('access_log_format', '').replace('"', '\\"') }}" \
          -o {{ servicedesk.dirs.temp }}/server.xml {{ servicedesk.dirs.temp }}/server.xsl server.xml
    - cwd: {{ servicedesk.dirs.install }}/conf
    - require:
      - file: servicedesk-install
      - file: servicedesk-server-xsl

servicedesk-server-xml:
  file.managed:
    - name: {{ servicedesk.dirs.install }}/conf/server.xml
    - source: {{ servicedesk.dirs.temp }}/server.xml
    - require:
      - cmd: servicedesk-server-xsl
    - watch_in:
      - service: servicedesk

servicedesk-dir:
  file.directory:
    - name: {{ servicedesk.dir }}
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

servicedesk-home:
  file.directory:
    - name: {{ servicedesk.dirs.home }}
    - user: {{ servicedesk.user }}
    - group: {{ servicedesk.group }}
    - mode: 755
    - require:
      - file: servicedesk-dir
    - makedirs: True

servicedesk-extractdir:
  file.directory:
    - name: {{ servicedesk.dirs.extract }}
    - use:
      - file: servicedesk-dir

servicedesk-temptdir:
  file.directory:
    - name: {{ servicedesk.dirs.temp }}
    - use:
      - file: servicedesk-dir

servicedesk-scriptdir:
  file.directory:
    - name: {{ servicedesk.dirs.scripts }}
    - use:
      - file: servicedesk-dir

{% for file in [ 'env.sh', 'start.sh', 'stop.sh' ] %}
servicedesk-script-{{ file }}:
  file.managed:
    - name: {{ servicedesk.dirs.scripts }}/{{ file }}
    - source: salt://atlassian-servicedesk/files/{{ file }}
    - user: {{ servicedesk.user }}
    - group: {{ servicedesk.group }}
    - mode: 755
    - template: jinja
    - defaults:
        config: {{ servicedesk|json }}
    - require:
      - file: servicedesk-scriptdir
      - group: servicedesk
      - user: servicedesk
    - watch_in:
      - service: servicedesk
{% endfor %}

{% if servicedesk.get('crowd') %}
servicedesk-crowd-properties:
  file.managed:
    - name: {{ servicedesk.dirs.install }}/atlassian-jira/WEB-INF/classes/crowd.properties
    - require:
      - file: servicedesk-install
    - watch_in:
      - service: servicedesk
    - contents: |
{%- for key, val in servicedesk.crowd.items() %}
        {{ key }}: {{ val }}
{%- endfor %}
{% endif %}

{% if servicedesk.managedb %}
servicedesk-dbconfig:
  file.managed:
    - name: {{ servicedesk.dirs.home }}/dbconfig.xml
    - source: salt://atlassian-servicedesk/files/dbconfig.xml
    - template: jinja
    - user: {{ servicedesk.user }}
    - group: {{ servicedesk.group }}
    - mode: 640
    - defaults:
        config: {{ servicedesk|json }}
    - require:
      - file: servicedesk-home
    - watch_in:
      - service: servicedesk
{% endif %}

{% for chmoddir in ['bin', 'work', 'temp', 'logs'] %}
servicedesk-permission-{{ chmoddir }}:
  file.directory:
    - name: {{ servicedesk.dirs.install }}/{{ chmoddir }}
    - user: {{ servicedesk.user }}
    - group: {{ servicedesk.group }}
    - recurse:
      - user
      - group
    - require:
      - file: servicedesk-install
      - group: servicedesk
      - user: servicedesk
    - require_in:
      - service: servicedesk
{% endfor %}

servicedesk-disable-JiraSeraphAuthenticator:
  file.blockreplace:
    - name: {{ servicedesk.dirs.install }}/atlassian-jira/WEB-INF/classes/seraph-config.xml
    - marker_start: 'CROWD:START - The authenticator below here will need to be commented'
    - marker_end: '<!-- CROWD:END'
    - content: {% if servicedesk.crowdSSO %}'    <!-- <authenticator class="com.atlassian.jira.security.login.JiraSeraphAuthenticator"/> -->'{% else %}'    <authenticator class="com.atlassian.jira.security.login.JiraSeraphAuthenticator"/>'{% endif %}
    - require:
      - file: servicedesk-install
    - watch_in:
      - service: servicedesk

servicedesk-enable-SSOSeraphAuthenticator:
  file.blockreplace:
    - name: {{ servicedesk.dirs.install }}/atlassian-jira/WEB-INF/classes/seraph-config.xml
    - marker_start: 'CROWD:START - If enabling Crowd SSO integration uncomment'
    - marker_end: '<!-- CROWD:END'
    - content: {% if servicedesk.crowdSSO %}'    <authenticator class="com.atlassian.jira.security.login.SSOSeraphAuthenticator"/>'{% else %}'    <!-- <authenticator class="com.atlassian.jira.security.login.SSOSeraphAuthenticator"/> -->'{% endif %}
    - require:
      - file: servicedesk-install
    - watch_in:
      - service: servicedesk
{% endif %}
