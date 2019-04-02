{% if pillar['prometheus'] is defined and pillar['prometheus'] is not none %}
docker_install_1:
  pkgrepo.managed:
    - humanname: Docker CE Repository
    - name: deb [arch=amd64] https://download.docker.com/linux/ubuntu {{ grains['oscodename'] }} stable
    - file: /etc/apt/sources.list.d/docker-ce.list
    - key_url: https://download.docker.com/linux/ubuntu/gpg

docker_install_2:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - docker-ce: '{{ pillar['prometheus']['docker-ce_version'] }}*'
        - python-docker

docker_install_3:
  service.running:
    - name: docker

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
                    auth_basic "Prometheus";
                    auth_basic_user_file /etc/nginx/{{ domain['name'] }}-{{ instance['name'] }}.htpasswd;
      {%- endif %}
                    proxy_pass http://localhost:{{ instance['port'] }}/{{ instance['name'] }}/;
                }
      {% if instance['pushgateway'] is defined and instance['pushgateway'] is not none and instance['pushgateway']['enabled'] %}
                location /{{ instance['name'] }}/pushgateway/ {
        {%- if instance['auth'] is defined and instance['auth'] is not none %}
                    auth_basic "Prometheus";
                    auth_basic_user_file /etc/nginx/{{ domain['name'] }}-{{ instance['name'] }}.htpasswd;
        {%- endif %}
                    # web route has bugs in 0.7.0, using nginx sub_filter for now as workaround, has to be removed later
                    sub_filter_once off;
                    sub_filter 'src="/static/' 'src="/{{ instance['name'] }}/pushgateway/static/';
                    sub_filter 'href="/static/' 'href="/{{ instance['name'] }}/pushgateway/static/';
                    #proxy_pass http://localhost:{{ instance['pushgateway']['port'] }}/{{ instance['name'] }}/pushgateway/;
                    proxy_pass http://localhost:{{ instance['pushgateway']['port'] }}/;
                }
      {%- endif %}
    {%- endfor %}
  {%- endfor %}
            }
        }

  {%- for domain in pillar['prometheus']['domains'] %}
nginx_domain_index_{{ loop.index }}:
  file.managed:
    - name: /opt/prometheus/{{ domain['name'] }}/index.html
    - contents: |
    {%- for instance in domain['instances'] %}
        <a href="{{ instance['name'] }}/">{{ instance['name'] }}</a><br>
    {%- endfor %}
  {%- endfor %}

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

prometheus_container_{{ loop.index }}_{{ i_loop.index }}:
  docker_container.running:
    - name: prometheus-{{ domain['name'] }}-{{ instance['name'] }}
    - user: root
    - image: {{ instance['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - {{ instance['port'] }}:9090/tcp
    - binds:
        - /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}:/prometheus-data:rw
    - watch:
        - /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}/etc/prometheus.yml
    - command: --config.file=/prometheus-data/etc/prometheus.yml --storage.tsdb.path=/prometheus-data --web.external-url=https://{{ domain['name'] }}/{{ instance['name'] }}/

      {% if instance['pushgateway'] is defined and instance['pushgateway'] is not none and instance['pushgateway']['enabled'] %}
prometheus_pushgateway_container_{{ loop.index }}_{{ i_loop.index }}:
  docker_container.running:
    - name: pushgateway-{{ domain['name'] }}-{{ instance['name'] }}
    - user: root
    - image: {{ instance['pushgateway']['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - {{ instance['pushgateway']['port'] }}:9091/tcp
    - binds:
        - /opt/prometheus/{{ domain['name'] }}/{{ instance['name'] }}-pushgateway:/pushgateway-data:rw
    # web route has bugs in 0.7.0, using nginx sub_filter for now as workaround, has to be removed later
    #- command: --persistence.file=/pushgateway-data/persistence_file --web.route-prefix=/{{ instance['name'] }}/pushgateway --web.telemetry-path=/{{ instance['name'] }}/pushgateway/metrics
    - command: --persistence.file=/pushgateway-data/persistence_file
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
