{% if pillar['prometheus'] is defined and pillar['prometheus'] is not none %}

  {% from "acme/macros.jinja" import verify_and_issue %}

  {%- if pillar["docker-ce"] is not defined %}
    {%- set docker_ce = {"version": pillar["prometheus"]["docker-ce_version"],
                         "daemon_json": '{ "iptables": false, "default-address-pools": [ {"base": "172.16.0.0/12", "size": 24} ] }'} %}
  {%- endif %}
  {%- include "docker-ce/docker-ce.sls" with context %}

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx
      - apache2-utils

  {%- for domain in pillar['prometheus']['domains'] %}
    {%- set a_loop = loop %}
    {%- for instance in domain['instances'] %}
      {%- set b_loop = loop %}
      {%- if instance['auth'] is defined and instance['auth'] is not none %}
        {%- for user in instance['auth'] %}
          {%- set c_loop = loop %}
          {%- for user_name, user_pass in user.items() %}
nginx_htaccess_user_{{ a_loop.index }}_{{ b_loop.index }}_{{ c_loop.index }}_{{ loop.index }}:
  webutil.user_exists:
    - name: '{{ user_name }}'
    - password: '{{ user_pass }}'
    - htpasswd_file: /etc/nginx/{{ domain['name'] }}-{{ instance['name'] }}.htpasswd
    - force: True
    - runas: root
          {%- endfor %}
        {%- endfor %}
      {%- endif %}
    {%- endfor %}
  {%- endfor %}

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
            server {
                listen 80;
                return 301 https://$host$request_uri;
            }
  {%- for domain in pillar['prometheus']['domains'] %}
            server {
                listen 443 ssl;
                server_name {{ domain['name'] }};
                root /opt/prometheus/{{ domain['name'] }};
                index index.html;
                ssl_certificate /opt/acme/cert/prometheus_{{ domain['name'] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/prometheus_{{ domain['name'] }}_key.key;
    {%- for instance in domain['instances'] %}
                location /{{ instance['name'] }}/ {
      {%- if instance['auth'] is defined and instance['auth'] is not none %}
                    auth_basic "Prometheus {{ instance['name'] }}";
                    auth_basic_user_file /etc/nginx/{{ domain['name'] }}-{{ instance['name'] }}.htpasswd;
      {%- endif %}
                    proxy_pass http://localhost:{{ instance['port'] }}/{{ instance['name'] }}/;
                }
      {% if instance['pushgateway'] is defined and instance['pushgateway'] is not none and instance['pushgateway']['enabled'] %}
                location /{{ instance['name'] }}/pushgateway/ {
        {%- if instance['auth'] is defined and instance['auth'] is not none %}
                    auth_basic "Prometheus {{ instance['name'] }}";
                    auth_basic_user_file /etc/nginx/{{ domain['name'] }}-{{ instance['name'] }}.htpasswd;
        {%- endif %}
                    # web route has bugs in 0.7.0, using nginx sub_filter for now as workaround, has to be removed later
                    #proxy_pass http://localhost:{{ instance['pushgateway']['port'] }}/{{ instance['name'] }}/pushgateway/;
                    sub_filter_once off;
                    sub_filter 'src="/static/' 'src="/{{ instance['name'] }}/pushgateway/static/';
                    sub_filter 'href="/static/' 'href="/{{ instance['name'] }}/pushgateway/static/';
                    proxy_pass http://localhost:{{ instance['pushgateway']['port'] }}/;
                }
      {%- endif %}
      {% if instance['statsd-exporter'] is defined and instance['statsd-exporter'] is not none and instance['statsd-exporter']['enabled'] %}
                location /{{ instance['name'] }}/statsd-exporter/ {
        {%- if instance['auth'] is defined and instance['auth'] is not none %}
                    auth_basic "Prometheus {{ instance['name'] }}";
                    auth_basic_user_file /etc/nginx/{{ domain['name'] }}-{{ instance['name'] }}.htpasswd;
        {%- endif %}
                    # web route is not even planned for statsd-exporter, using nginx sub_filter
                    sub_filter_once off;
                    sub_filter 'href="/metrics' 'href="/{{ instance['name'] }}/statsd-exporter/metrics';
                    proxy_pass http://localhost:{{ instance['statsd-exporter']['port'] }}/;
                }
      {%- endif %}
      {% if instance['blackbox-exporter'] is defined and instance['blackbox-exporter'] is not none and instance['blackbox-exporter']['enabled'] %}
                location /{{ instance['name'] }}/blackbox-exporter/ {
        {%- if instance['auth'] is defined and instance['auth'] is not none %}
                    auth_basic "Prometheus {{ instance['name'] }}";
                    auth_basic_user_file /etc/nginx/{{ domain['name'] }}-{{ instance['name'] }}.htpasswd;
        {%- endif %}
                    # web route is not even planned for blackbox-exporter, using nginx sub_filter
                    sub_filter_once off;
                    sub_filter 'href="/metrics' 'href="/{{ instance['name'] }}/blackbox-exporter/metrics';
                    proxy_pass http://localhost:{{ instance['blackbox-exporter']['port'] }}/;
                }
      {%- endif %}
      {% if instance['pagespeed-exporter'] is defined and instance['pagespeed-exporter'] is not none and instance['pagespeed-exporter']['enabled'] %}
                location /{{ instance['name'] }}/pagespeed-exporter/ {
        {%- if instance['auth'] is defined and instance['auth'] is not none %}
                    auth_basic "Prometheus {{ instance['name'] }}";
                    auth_basic_user_file /etc/nginx/{{ domain['name'] }}-{{ instance['name'] }}.htpasswd;
        {%- endif %}
                    # web route is not even planned for pagespeed-exporter, using nginx sub_filter
                    sub_filter_once off;
                    sub_filter 'href="/probe' 'href="/{{ instance['name'] }}/pagespeed-exporter/probe';
                    sub_filter 'href="/metrics' 'href="/{{ instance['name'] }}/pagespeed-exporter/metrics';
                    proxy_pass http://localhost:{{ instance['pagespeed-exporter']['port'] }}/;
                }
      {%- endif %}
      {% if instance['redis-exporter'] is defined and instance['redis-exporter'] is not none and instance['redis-exporter']['enabled'] %}
                location /{{ instance['name'] }}/redis-exporter/ {
        {%- if instance['auth'] is defined and instance['auth'] is not none %}
                    auth_basic "Prometheus {{ instance['name'] }}";
                    auth_basic_user_file /etc/nginx/{{ domain['name'] }}-{{ instance['name'] }}.htpasswd;
        {%- endif %}
                    # web route is not even planned for redis-exporter, using nginx sub_filter
                    sub_filter_once off;
                    sub_filter 'href="/scrape' 'href="/{{ instance['name'] }}/redis-exporter/scrape';
                    sub_filter 'href="/metrics' 'href="/{{ instance['name'] }}/redis-exporter/metrics';
                    proxy_pass http://localhost:{{ instance['redis-exporter']['port'] }}/;
                }
      {%- endif %}
    {%- endfor %}
  {%- endfor %}
            }
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- for domain in pillar['prometheus']['domains'] %}

    {{ verify_and_issue(domain["acme_account"], "prometheus", domain["name"]) }}

    {%- set i_loop = loop %}
    {%- for instance in domain['instances'] %}
prometheus_dir_{{ loop.index }}_{{ i_loop.index }}:
  file.directory:
    - name: /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}/etc
    - mode: 755
    - makedirs: True

      {% if instance['pushgateway'] is defined and instance['pushgateway'] is not none and instance['pushgateway']['enabled'] %}
prometheus_pushgateway_dir_{{ loop.index }}_{{ i_loop.index }}:
  file.directory:
    - name: /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}-pushgateway
    - mode: 755
    - makedirs: True
      {%- endif %}

      {% if instance['statsd-exporter'] is defined and instance['statsd-exporter'] is not none and instance['statsd-exporter']['enabled'] %}
prometheus_statsd-exporter_dir_{{ loop.index }}_{{ i_loop.index }}:
  file.directory:
    - name: /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}-statsd-exporter
    - mode: 755
    - makedirs: True

prometheus_statsd-exporter_config_{{ loop.index }}_{{ i_loop.index }}:
  file.serialize:
    - name: /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}-statsd-exporter/statsd_mapping.yml
    - user: root
    - group: root
    - mode: 644
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: yaml
    - dataset: {{ instance['statsd-exporter']['mapping-config'] }}
      {%- endif %}

      {% if instance['blackbox-exporter'] is defined and instance['blackbox-exporter'] is not none and instance['blackbox-exporter']['enabled'] %}
prometheus_blackbox-exporter_dir_{{ loop.index }}_{{ i_loop.index }}:
  file.directory:
    - name: /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}-blackbox-exporter
    - mode: 755
    - makedirs: True

prometheus_blackbox-exporter_config_{{ loop.index }}_{{ i_loop.index }}:
  file.serialize:
    - name: /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}-blackbox-exporter/config.yml
    - user: root
    - group: root
    - mode: 644
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: yaml
    - dataset: {{ instance['blackbox-exporter']['config'] }}
      {%- endif %}

      {% if instance['redis-exporter'] is defined and instance['redis-exporter'] is not none and instance['redis-exporter']['enabled'] %}
prometheus_redis-exporter_dir_{{ loop.index }}_{{ i_loop.index }}:
  file.directory:
    - name: /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}-redis-exporter
    - mode: 755
    - makedirs: True
        {%- if   'redis_password_file' in  instance['redis-exporter'] %}
prometheus_redis-exporter_password-file_{{ loop.index }}_{{ i_loop.index }}:
  file.serialize:
    - name: /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}-redis-exporter/redis-password-file.json
    - user: root
    - group: root
    - mode: 644
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: json
    - dataset: {{ instance['redis-exporter']['redis_password_file'] }}
        {%- endif %}
      {%- endif %}

prometheus_config_{{ loop.index }}_{{ i_loop.index }}:
  file.managed:
    - name: /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}/etc/prometheus.yml
    - mode: 644
    - user: root
    - group: root
    - contents: |
        {{ instance['config'] | indent(8) }}

docker_network_{{ loop.index }}_{{ i_loop.index }}:
  docker_network.present:
    - name: prometheus-{{ domain['name'] }}-{{ instance['name'] }}

prometheus_image_{{ loop.index }}_{{ i_loop.index }}:
  cmd.run:
    - name: docker pull {{ instance['image'] }}

prometheus_container_{{ loop.index }}_{{ i_loop.index }}:
  docker_container.running:
    - name: prometheus-{{ domain['name'] }}-{{ instance['name'] }}
    - user: root
    - image: {{ instance['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - networks:
        - prometheus-{{ domain['name'] }}-{{ instance['name'] }}
    - publish:
        - 127.0.0.1:{{ instance['port'] }}:9090/tcp
    - binds:
        - /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}:/prometheus-data:rw
    - watch:
        - /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}/etc/prometheus.yml
      {% if instance['retention_time'] is defined and instance['retention_time'] is not none %}
        {% set retention_time_arg = '--storage.tsdb.retention.time=' + instance['retention_time'] %}
      {% else %}
        {% set retention_time_arg = '' %}
      {% endif %}
    - command: --config.file=/prometheus-data/etc/prometheus.yml --storage.tsdb.path=/prometheus-data {{ retention_time_arg }} --web.external-url=https://{{ domain['name'] }}/{{ instance['name'] }}/ --web.enable-admin-api

prometheus_snapshot_cron_{{ loop.index }}_{{ i_loop.index }}:
  cron.present:
    - name: /bin/rm -rf /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}/snapshots/* && /usr/bin/curl -XPOST http://localhost:{{ instance['port'] }}/{{ instance['name'] }}/api/v1/admin/tsdb/snapshot
    - identifier: prometheus_snapshot_{{ domain['name'] }}_{{ instance['name'] }}
    - user: root
    - minute: 20
    - hour: 6

      {% if instance['pushgateway'] is defined and instance['pushgateway'] is not none and instance['pushgateway']['enabled'] %}
prometheus_pushgateway_image_{{ loop.index }}_{{ i_loop.index }}:
  cmd.run:
    - name: docker pull {{ instance['pushgateway']['image'] }}

prometheus_pushgateway_container_{{ loop.index }}_{{ i_loop.index }}:
  docker_container.running:
    - name: pushgateway-{{ domain['name'] }}-{{ instance['name'] }}
    - user: root
    - image: {{ instance['pushgateway']['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - networks:
        - prometheus-{{ domain['name'] }}-{{ instance['name'] }}
    - publish:
        - 127.0.0.1:{{ instance['pushgateway']['port'] }}:9091/tcp
    - binds:
        - /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}-pushgateway:/pushgateway-data:rw
    # web route has bugs in 0.7.0, using nginx sub_filter for now as workaround, has to be removed later
    #- command: --persistence.file=/pushgateway-data/persistence_file --web.route-prefix=/{{ instance['name'] }}/pushgateway --web.telemetry-path=/{{ instance['name'] }}/pushgateway/metrics
    - command: --persistence.file=/pushgateway-data/persistence_file
      {%- endif %}

      {% if instance['statsd-exporter'] is defined and instance['statsd-exporter'] is not none and instance['statsd-exporter']['enabled'] %}
prometheus_statsd-exporter_image_{{ loop.index }}_{{ i_loop.index }}:
  cmd.run:
    - name: docker pull {{ instance['statsd-exporter']['image'] }}

prometheus_statsd-exporter_container_{{ loop.index }}_{{ i_loop.index }}:
  docker_container.running:
    - name: statsd-exporter-{{ domain['name'] }}-{{ instance['name'] }}
    - user: root
    - image: {{ instance['statsd-exporter']['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - networks:
        - prometheus-{{ domain['name'] }}-{{ instance['name'] }}
    - publish:
        - 127.0.0.1:{{ instance['statsd-exporter']['port'] }}:9102/tcp
        - 0.0.0.0:{{ instance['statsd-exporter']['statsd_tcp_port'] }}:9125/tcp
        - 0.0.0.0:{{ instance['statsd-exporter']['statsd_udp_port'] }}:9125/udp
    - binds:
        - /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}-statsd-exporter:/statsd-exporter-data:rw
    - command: --statsd.mapping-config=/statsd-exporter-data/statsd_mapping.yml
      {%- endif %}
      {% if instance['blackbox-exporter'] is defined and instance['blackbox-exporter'] is not none and instance['blackbox-exporter']['enabled'] %}
prometheus_blackbox-exporter_image_{{ loop.index }}_{{ i_loop.index }}:
  cmd.run:
    - name: docker pull {{ instance['blackbox-exporter']['image'] }}

prometheus_blackbox-exporter_container_{{ loop.index }}_{{ i_loop.index }}:
  docker_container.running:
    - name: blackbox-exporter-{{ domain['name'] }}-{{ instance['name'] }}
    - user: root
    - image: {{ instance['blackbox-exporter']['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - networks:
        - prometheus-{{ domain['name'] }}-{{ instance['name'] }}
    - publish:
        - 127.0.0.1:{{ instance['blackbox-exporter']['port'] }}:9115/tcp
    - binds:
        - /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}-blackbox-exporter/config.yml:/blackbox-exporter/config.yml:rw
    - command: --config.file=/blackbox-exporter/config.yml
      {%- endif %}
      {% if instance['pagespeed-exporter'] is defined and instance['pagespeed-exporter'] is not none and instance['pagespeed-exporter']['enabled'] %}
prometheus_pagespeed-exporter_image_{{ loop.index }}_{{ i_loop.index }}:
  cmd.run:
    - name: docker pull {{ instance['pagespeed-exporter']['image'] }}

prometheus_pagespeed-exporter_container_{{ loop.index }}_{{ i_loop.index }}:
  docker_container.running:
    - name: pagespeed-exporter-{{ domain['name'] }}-{{ instance['name'] }}
    - user: root
    - image: {{ instance['pagespeed-exporter']['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - networks:
        - prometheus-{{ domain['name'] }}-{{ instance['name'] }}
    - publish:
        - 127.0.0.1:{{ instance['pagespeed-exporter']['port'] }}:9271/tcp
        {%- if 'apikey' in instance['pagespeed-exporter'] %}
    - command: -api-key {{ instance['pagespeed-exporter']['apikey'] }}
        {%- endif %}
      {%- endif %}

      {% if instance['redis-exporter'] is defined and instance['redis-exporter'] is not none and instance['redis-exporter']['enabled'] %}
prometheus_redis-exporter_image_{{ loop.index }}_{{ i_loop.index }}:
  cmd.run:
    - name: docker pull {{ instance['redis-exporter']['image'] }}

prometheus_redis-exporter_container_{{ loop.index }}_{{ i_loop.index }}:
  docker_container.running:
    - name: redis-exporter-{{ domain['name'] }}-{{ instance['name'] }}
    - image: {{ instance['redis-exporter']['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - networks:
        - prometheus-{{ domain['name'] }}-{{ instance['name'] }}
    - publish:
        - 127.0.0.1:{{ instance['redis-exporter']['port'] }}:9121/tcp
        {%- if   'redis_password_file' in  instance['redis-exporter']    and 'command' in     instance['redis-exporter'] %}
    - binds:
        - /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}-redis-exporter/redis-password-file.json:/redis-exporter/redis-password-file.json:rw
    - watch:
        - /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}-redis-exporter/redis-password-file.json
    - command: --redis.addr= --redis.password-file=/redis-exporter/redis-password-file.json {{ instance['redis-exporter']['command'] }}
          {%- elif 'redis_password_file' not in instance['redis-exporter'] and 'command' in     instance['redis-exporter'] %}
    - command: --redis.addr= --redis.password-file=/redis-exporter/redis-password-file.json {{ instance['redis-exporter']['command'] }}
          {%- elif 'redis_password_file' in     instance['redis-exporter'] and 'command' not in instance['redis-exporter'] %}
    - binds:
        - /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}-redis-exporter/redis-password-file.json:/redis-exporter/redis-password-file.json:rw
    - watch:
        - /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}-redis-exporter/redis-password-file.json
    - command: --redis.addr= --redis.password-file=/redis-exporter/redis-password-file.json
          {%- elif 'redis_password_file' not in  instance['redis-exporter'] and 'command' not in instance['redis-exporter'] %}
    - command: --redis.addr= --redis.password-file=/redis-exporter/redis-password-file.json
          {%- endif %}
      {%- endif %}

    {%- endfor %}
  {%- endfor %}

  {%- for domain in pillar['prometheus']['domains'] %}
nginx_domain_index_{{ loop.index }}:
  file.managed:
    - name: /opt/prometheus/{{ domain['name'] }}/index.html
    - contents: |
    {%- if 'default_instance' in domain %}
        <meta http-equiv="refresh" content="0; url='https://{{ domain['name'] }}/{{ domain['default_instance'] }}/targets'" />
    {%- endif %}
    {%- for instance in domain['instances'] %}
        <a href="{{ instance['name'] }}/">{{ instance['name'] }}</a><br>
      {% if instance['pushgateway'] is defined and instance['pushgateway'] is not none and instance['pushgateway']['enabled'] %}
        <a href="{{ instance['name'] }}/pushgateway/">{{ instance['name'] }}/pushgateway</a><br>
      {%- endif %}
      {% if instance['statsd-exporter'] is defined and instance['statsd-exporter'] is not none and instance['statsd-exporter']['enabled'] %}
        <a href="{{ instance['name'] }}/statsd-exporter/">{{ instance['name'] }}/statsd-exporter</a><br>
      {%- endif %}
      {% if instance['blackbox-exporter'] is defined and instance['blackbox-exporter'] is not none and instance['blackbox-exporter']['enabled'] %}
        <a href="{{ instance['name'] }}/blackbox-exporter/">{{ instance['name'] }}/blackbox-exporter</a><br>
      {%- endif %}
      {% if instance['pagespeed-exporter'] is defined and instance['pagespeed-exporter'] is not none and instance['pagespeed-exporter']['enabled'] %}
        <a href="{{ instance['name'] }}/pagespeed-exporter/">{{ instance['name'] }}/pagespeed-exporter</a><br>
      {%- endif %}
      {% if instance['redis-exporter'] is defined and instance['redis-exporter'] is not none and instance['redis-exporter']['enabled'] %}
        <a href="{{ instance['name'] }}/redis-exporter/">{{ instance['name'] }}/redis-exporter</a><br>
      {%- endif %}
    {%- endfor %}
  {%- endfor %}

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
