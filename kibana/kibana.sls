{% if pillar['kibana'] is defined and pillar['kibana'] is not none %}

  {%- if pillar["docker-ce"] is not defined %}
    {%- set docker_ce = {"version": pillar["kibana"]["docker-ce_version"],
                         "daemon_json": '{"iptables": false}'} %}
  {%- endif %}
  {%- include "docker-ce/docker-ce.sls" with context %}

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
        }

        http {
            server {
                listen 80;
                return 301 https://$host$request_uri;
            }
  {%- for domain in pillar['kibana']['domains'] %}
            server {
                listen 443 ssl;
                server_name {{ domain['name'] }};
                root /opt/kibana/{{ domain['name'] }};
                index index.html;
                ssl_certificate /opt/acme/cert/kibana_{{ domain['name'] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/kibana_{{ domain['name'] }}_key.key;
    {%- for instance in domain['instances'] %}
                location /{{ instance['name'] }}/ {
                    proxy_pass http://localhost:{{ instance['port'] }}/;
                }
    {%- endfor %}
  {%- endfor %}
            }
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- for domain in pillar['kibana']['domains'] %}
nginx_cert_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: 'openssl verify -CAfile /opt/acme/cert/kibana_{{ domain['name'] }}_ca.cer /opt/acme/cert/kibana_{{ domain['name'] }}_fullchain.cer 2>&1 | grep -q -i -e error -e cannot; [ ${PIPESTATUS[1]} -eq 0 ] && /opt/acme/home/acme_local.sh --cert-file /opt/acme/cert/kibana_{{ domain['name'] }}_cert.cer --key-file /opt/acme/cert/kibana_{{ domain['name'] }}_key.key --ca-file /opt/acme/cert/kibana_{{ domain['name'] }}_ca.cer --fullchain-file /opt/acme/cert/kibana_{{ domain['name'] }}_fullchain.cer --issue -d {{ domain['name'] }} || true'

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

  {%- for domain in pillar['kibana']['domains'] %}
kibana_domain_dir_{{ loop.index }}:
  file.directory:
    - name: /opt/kibana/{{ domain['name'] }}
    - mode: 755
    - makedirs: True

nginx_instance_index_{{ loop.index }}:
  file.managed:
    - name: /opt/kibana/{{ domain['name'] }}/index.html
    - contents: |
    {%- for instance in domain['instances'] %}
        <a href="{{ instance['name'] }}/">{{ instance['name'] }}</a><br>
    {%- endfor %}
  {%- endfor %}

  {%- for domain in pillar['kibana']['domains'] %}
    {%- set i_loop = loop %}
    {%- for instance in domain['instances'] %}
kibana_config_dir_{{ loop.index }}_{{ i_loop.index }}:
  file.directory:
    - name: /opt/kibana/{{ domain['name'] }}/{{ instance['name'] }}/config
    - mode: 755
    - user: 1000
    - group: 0
    - makedirs: True

kibana_config_{{ loop.index }}_{{ i_loop.index }}:
  file.managed:
    - name: /opt/kibana/{{ domain['name'] }}/{{ instance['name'] }}/config/kibana.yml
    - user: 1000
    - group: 0
    - mode: 644
    - contents: |
        elasticsearch.hosts: ['{{ instance['elasticsearch']['url'] }}']
        elasticsearch.username: {{ instance['elasticsearch']['username'] }}
        elasticsearch.password: {{ instance['elasticsearch']['password'] }}
        server.basePath: /{{ instance['name'] }}
        server.name: {{ domain['name'] }}-{{ instance['name'] }}
        server.port: {{ instance['port'] }}
        server.host: 0.0.0.0
        logging.verbose: true
        {{ instance['config'] }}

kibana_image_{{ loop.index }}_{{ i_loop.index }}:
  cmd.run:
    - name: docker pull {{ instance['image'] }}

kibana_container_{{ loop.index }}_{{ i_loop.index }}:
  docker_container.running:
    - name: kibana-{{ domain['name'] }}-{{ instance['name'] }}
    - user: root
    - image: {{ instance['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - command: /usr/local/bin/kibana-docker --allow-root
    - publish:
        - 127.0.0.1:{{ instance['port'] }}:{{ instance['port'] }}/tcp
    - binds:
        - /opt/kibana/{{ domain['name'] }}/{{ instance['name'] }}/config/kibana.yml:/usr/share/kibana/config/kibana.yml
    - watch:
        - /opt/kibana/{{ domain['name'] }}/{{ instance['name'] }}/config/kibana.yml

    {%- endfor %}
  {%- endfor %}

{% endif %}
