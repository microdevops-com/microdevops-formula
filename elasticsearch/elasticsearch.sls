{% if pillar['elasticsearch'] is defined and pillar['elasticsearch'] is not none %}
set_vm.max_map_count:
  cmd.run:
    - shell: /bin/bash
    - name: sysctl -w vm.max_map_count=262144

save_vm.max_map_count:
  file.replace:
    - name: '/etc/sysctl.conf'
    - pattern: '^ *vm.max_map_count=.*$'
    - repl: 'vm.max_map_count=262144'
    - append_if_not_found: True

docker_install_1:
  file.directory:
    - name: /etc/docker
    - mode: 700

docker_install_2:
  file.managed:
    - name: /etc/docker/daemon.json
    - contents: |
        { "iptables": false, "default-address-pools": [ {"base": "172.16.0.0/12", "size": 24} ] }

docker_install_3:
  pkgrepo.managed:
    - humanname: Docker CE Repository
    - name: deb [arch=amd64] https://download.docker.com/linux/{{ grains['os']|lower }} {{ grains['oscodename'] }} stable
    - file: /etc/apt/sources.list.d/docker-ce.list
    - key_url: https://download.docker.com/linux/{{ grains['os']|lower }}/gpg

docker_install_4:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs: 
        - docker-ce: '{{ pillar['elasticsearch']['docker-ce_version'] }}*'
        - python3-pip
                
docker_pip_install:
  pip.installed:
    - name: docker-py >= 1.10
    - reload_modules: True


docker_install_5:
  service.running:
    - name: docker

docker_install_6:
  cmd.run:
    - name: systemctl restart docker
    - onchanges:
        - file: /etc/docker/daemon.json

  {%- for node_name, node_ip in pillar['elasticsearch']['nodes']['ips'].items() %}
    {# No need to make self link #}
    {%- if grains['fqdn'] != node_name %}
hosts_node_{{ loop.index }}:
  host.present:
    - name: {{ node_name }}
    - ip: {{ node_ip }}
    {%- endif %}

  {%- endfor %}

  {%- if grains['fqdn'] in pillar['elasticsearch']['nodes']['ingest'] %}
nginx_install:
  pkg.installed:
    - pkgs:
      - nginx
      - apache2-utils

    {%- for domain in pillar['elasticsearch']['domains'] %}
      {%- set a_loop = loop %}
      {%- for cluster in domain['clusters'] %}
        {%- set b_loop = loop %}
        {%- if cluster['auth'] is defined and cluster['auth'] is not none %}
          {%- for user in cluster['auth'] %}
            {%- set c_loop = loop %}
            {%- for user_name, user_pass in user.items() %}
nginx_htaccess_user_{{ a_loop.index }}_{{ b_loop.index }}_{{ c_loop.index }}_{{ loop.index }}:
  webutil.user_exists:
    - name: '{{ user_name }}'
    - password: '{{ user_pass }}'
    - htpasswd_file: /etc/nginx/{{ domain['name'] }}-{{ cluster['name'] }}.htpasswd
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
    {%- for domain in pillar['elasticsearch']['domains'] %}
            server {
                listen 443 ssl;
                server_name {{ domain['name'] }};
                root /opt/elasticsearch/{{ domain['name'] }};
                index index.html;
                ssl_certificate /opt/acme/cert/elasticsearch_{{ domain['name'] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/elasticsearch_{{ domain['name'] }}_key.key;
      {%- for cluster in domain['clusters'] %}
                location /{{ cluster['name'] }}/ {
        {%- if cluster['auth'] is defined and cluster['auth'] is not none %}
                    auth_basic "Elasticsearch {{ cluster['name'] }}";
                    auth_basic_user_file /etc/nginx/{{ domain['name'] }}-{{ cluster['name'] }}.htpasswd;
        {%- endif %}
                    proxy_pass http://localhost:{{ cluster['ports']['http'] }}/;
                }
      {%- endfor %}
    {%- endfor %}
            }
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

    {%- for domain in pillar['elasticsearch']['domains'] %}
nginx_cert_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ domain["acme_account"] }}/verify_and_issue.sh elasticsearch {{ domain['name'] }}"
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

    {%- for domain in pillar['elasticsearch']['domains'] %}
elasticsearch_domain_dir_{{ loop.index }}:
  file.directory:
    - name: /opt/elasticsearch/{{ domain['name'] }}
    - mode: 755
    - makedirs: True

nginx_cluster_index_{{ loop.index }}:
  file.managed:
    - name: /opt/elasticsearch/{{ domain['name'] }}/index.html
    - contents: |
      {%- for cluster in domain['clusters'] %}
        <a href="{{ cluster['name'] }}/">{{ cluster['name'] }}</a><br>
      {%- endfor %}
    {%- endfor %}

  {% endif %}

  {%- for domain in pillar['elasticsearch']['domains'] %}
    {%- set i_loop = loop %}
    {%- for cluster in domain['clusters'] %}
elasticsearch_config_dir_{{ loop.index }}_{{ i_loop.index }}:
  file.directory:
    - name: /opt/elasticsearch/{{ domain['name'] }}/{{ cluster['name'] }}/config
    - mode: 755
    - user: 1000
    - group: 0
    - makedirs: True

elasticsearch_data_dir_{{ loop.index }}_{{ i_loop.index }}:
  file.directory:
    - name: /opt/elasticsearch/{{ domain['name'] }}/{{ cluster['name'] }}/data
    - mode: 755
    - user: 1000
    - group: 0
    - makedirs: True

elasticsearch_config_{{ loop.index }}_{{ i_loop.index }}:
  file.managed:
    - name: /opt/elasticsearch/{{ domain['name'] }}/{{ cluster['name'] }}/config/elasticsearch.yml
    - user: 1000
    - group: 0
    - mode: 644
    - contents: |
        {% if grains['fqdn'] in pillar['elasticsearch']['nodes']['master'] %}node.master: true{% else %}node.master: false{% endif %}
        node.voting_only: false
        {% if grains['fqdn'] in pillar['elasticsearch']['nodes']['data'] %}node.data: true{% else %}node.data: false{% endif %}
        {% if grains['fqdn'] in pillar['elasticsearch']['nodes']['ingest'] %}node.ingest: true{% else %}node.ingest: false{% endif %}
        node.ml: false
        xpack.ml.enabled: false
        cluster.remote.connect: true
        node.name: {{ grains['fqdn'] }}
        cluster.name: {{ domain['name'] }}-{{ cluster['name'] }}
        discovery.seed_hosts: "{% for master in pillar['elasticsearch']['nodes']['master'] %}{% if master != grains['fqdn'] %}{{ master }}:{{ cluster['ports']['transport'] }}{% if not loop.last %},{% endif %}{% endif %}{% endfor %}"
        cluster.initial_master_nodes: "{% for master in pillar['elasticsearch']['nodes']['master'] %}{{ master }}{% if not loop.last %},{% endif %}{% endfor %}"
        bootstrap.memory_lock: "true"
        network.host: 0.0.0.0
        network.publish_host: {{ pillar['elasticsearch']['nodes']['ips'][grains['fqdn']] }}
        http.port: {{ cluster['ports']['http'] }}
        transport.port: {{ cluster['ports']['transport'] }}
        {{ cluster['config'] }}

elasticsearch_image_{{ loop.index }}_{{ i_loop.index }}:
  cmd.run:
    - name: docker pull {{ cluster['image'] }}

elasticsearch_container_{{ loop.index }}_{{ i_loop.index }}:
  docker_container.running:
    - name: elasticsearch-{{ domain['name'] }}-{{ cluster['name'] }}
    - user: root
    - image: {{ cluster['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - 0.0.0.0:{{ cluster['ports']['http'] }}:{{ cluster['ports']['http'] }}/tcp
        - 0.0.0.0:{{ cluster['ports']['transport'] }}:{{ cluster['ports']['transport'] }}/tcp
    - binds:
        - /opt/elasticsearch/{{ domain['name'] }}/{{ cluster['name'] }}/config/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml
        - /opt/elasticsearch/{{ domain['name'] }}/{{ cluster['name'] }}/data:/usr/share/elasticsearch/data:rw
    - watch:
        - /opt/elasticsearch/{{ domain['name'] }}/{{ cluster['name'] }}/config/elasticsearch.yml
    - environment:
        - ES_JAVA_OPTS: {{ pillar['elasticsearch']['java_opts'] }}
    - ulimits:
        - memlock=-1:-1
        - nofile=65535:65535
    - extra_hosts:
        {%- for node_name, node_ip in pillar['elasticsearch']['nodes']['ips'].items() %}
          {% if grains['fqdn'] != node_name %}- {{ node_name }}:{{ node_ip }}{% endif %}
          {% if grains['fqdn'] == node_name %}- {{ node_name }}:127.0.0.1{% endif %}
        {%- endfor %}

    {%- endfor %}
  {%- endfor %}

{% endif %}
