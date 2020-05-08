{% if pillar['prometheus'] is defined and pillar['prometheus'] is not none %}
docker_install_00:
  file.directory:
    - name: /etc/docker
    - mode: 700

docker_install_01:
  file.managed:
    - name: /etc/docker/daemon.json
    - contents: |
        {"iptables": false}

docker_install_1:
  pkgrepo.managed:
    - humanname: Docker CE Repository
    - name: deb [arch=amd64] https://download.docker.com/linux/{{ grains['os']|lower }} {{ grains['oscodename'] }} stable
    - file: /etc/apt/sources.list.d/docker-ce.list
    - key_url: https://download.docker.com/linux/{{ grains['os']|lower }}/gpg

docker_install_2:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - docker-ce: '{{ pillar['prometheus']['docker-ce_version'] }}*'
        - python-pip
        - curl
        # xenial has 1.9 package, it is not sufficiant for docker networks, so we need installing pip manually
        #- python-docker
                
docker_pip_install:
  pip.installed:
    - name: docker-py >= 1.10
    - reload_modules: True

docker_install_3:
  service.running:
    - name: docker

docker_install_4:
  cmd.run:
    - name: 'systemctl restart docker'
    - onchanges:
        - file: /etc/docker/daemon.json

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
    {%- endfor %}
  {%- endfor %}
            }
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- for domain in pillar['prometheus']['domains'] %}
nginx_cert_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: 'openssl verify -CAfile /opt/acme/cert/prometheus_{{ domain['name'] }}_ca.cer /opt/acme/cert/prometheus_{{ domain['name'] }}_fullchain.cer 2>&1 | grep -q -i -e error; [ ${PIPESTATUS[1]} -eq 0 ] && /opt/acme/home/acme_local.sh --cert-file /opt/acme/cert/prometheus_{{ domain['name'] }}_cert.cer --key-file /opt/acme/cert/prometheus_{{ domain['name'] }}_key.key --ca-file /opt/acme/cert/prometheus_{{ domain['name'] }}_ca.cer --fullchain-file /opt/acme/cert/prometheus_{{ domain['name'] }}_fullchain.cer --issue -d {{ domain['name'] }} || true'

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

prometheus_config_{{ loop.index }}_{{ i_loop.index }}:
  file.serialize:
    - name: /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}/etc/prometheus.yml
    - user: root
    - group: root
    - mode: 644
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: yaml
    - dataset: {{ instance['config'] }}
    
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

    {%- endfor %}
  {%- endfor %}

  {%- for domain in pillar['prometheus']['domains'] %}
nginx_domain_index_{{ loop.index }}:
  file.managed:
    - name: /opt/prometheus/{{ domain['name'] }}/index.html
    - contents: |
    {%- for instance in domain['instances'] %}
        <a href="{{ instance['name'] }}/">{{ instance['name'] }}</a><br>
      {% if instance['pushgateway'] is defined and instance['pushgateway'] is not none and instance['pushgateway']['enabled'] %}
        <a href="{{ instance['name'] }}/pushgateway/">{{ instance['name'] }}/pushgateway</a><br>
      {%- endif %}
      {% if instance['statsd-exporter'] is defined and instance['statsd-exporter'] is not none and instance['statsd-exporter']['enabled'] %}
        <a href="{{ instance['name'] }}/statsd-exporter/">{{ instance['name'] }}/statsd-exporter</a><br>
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
