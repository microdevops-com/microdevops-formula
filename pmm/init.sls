{% if pillar['pmm'] is defined %}
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
        - docker-ce: '{{ pillar['pmm']['docker-ce_version'] }}*'
        - python3-pip
                
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
nginx_files_1:
  file.absent:
    - name: /etc/nginx/sites-enabled/default
nginx_files_2:
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
  {%- for domain in pillar['pmm']['domains'] %}
            server {
                listen 443 ssl;
                server_name {{ domain['name'] }};
                ssl_certificate /opt/acme/cert/{{ domain['name'] }}/fullchain.cer;
                 ssl_certificate_key /opt/acme/cert/{{ domain['name'] }}/{{ domain['name'] }}.key;
    {%- for instance in domain['instances'] %}
                location / {
                    proxy_pass http://localhost:{{ instance['port'] }}/;
                 }
    {%- endfor %}
  {%- endfor %}
            }
        }
    {%- for domain in pillar['pmm']['domains'] %}
    {%- set i_loop = loop %}
    {%- for instance in domain['instances'] %}
percona_pmm_etc_dir_{{ loop.index }}_{{ i_loop.index }}:
  file.directory:
    - name: /opt/pmm/{{ domain['name'] }}/{{ instance['name'] }}/etc
    - mode: 755
    - makedirs: True
percona_pmm_config_{{ loop.index }}_{{ i_loop.index }}:
  file.managed:
    - name: /opt/pmm/{{ domain['name'] }}/{{ instance['name'] }}/etc/grafana.ini
    - user: root
    - group: root
    - mode: 644
    - contents: {{ instance['config'] | yaml_encode }}
percona_pmm_image_{{ loop.index }}_{{ i_loop.index }}:
  cmd.run:
    - name: docker pull {{ instance['image'] }}
percona_pmm_container_{{ loop.index }}_{{ i_loop.index }}:
  docker_container.running:
    - name: percona-{{ domain['name'] }}
    - user: root
    - image: {{ instance['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - 127.0.0.1:{{ instance['port'] }}:80/tcp
    - binds:
        - /opt/pmm/{{ domain['name'] }}/{{ instance['name'] }}/etc:/etc/grafana:rw
    - watch:
        - /opt/pmm/{{ domain['name'] }}/{{ instance['name'] }}/etc/grafana.ini
dump_pmm_cron:
  cron.present:
    - name: docker exec -i percona-{{ domain['name'] }} /bin/bash -c "pg_dump --username postgres pmm-managed" > /var/pmm_backup/pmm-managed.sql
    - user: root
    - minute: 0
    - hour: 3
{%- endfor %}
  {%- endfor %}
nginx_cert:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["pmm"]["acme_account"] }}/verify_and_issue.sh percona_pmm {{ pillar["pmm"]["servername"] }}"
nginx_reload:
  cmd.run:
    - runas: root
    - name: service nginx configtest && service nginx restart
nginx_reload_cron:
  cron.present:
    - name: /usr/sbin/service nginx configtest && /usr/sbin/service nginx reload
    - identifier: nginx_reload
    - user: root
    - minute: 15
    - hour: 6
dir_for_backups:
  file.directory:
    - name: /var/pmm_backup
    - user: root
    - mode: 755
    - makedirs: True
{% endif %}
