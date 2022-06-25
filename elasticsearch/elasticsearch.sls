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
    {%- if grains['id'] != node_name %}
hosts_node_{{ loop.index }}:
  host.present:
    - name: {{ node_name }}
    - ip: {{ node_ip }}
    {%- endif %}
  {%- endfor %}

elasticsearch_config_dir:
  file.directory:
    - name: /opt/elasticsearch/{{ pillar['elasticsearch']['cluster'] }}/config
    - mode: 755
    - user: 1000
    - group: 0
    - makedirs: True

elasticsearch_data_dir:
  file.directory:
    - name: /opt/elasticsearch/{{ pillar['elasticsearch']['cluster'] }}/data
    - mode: 755
    - user: 1000
    - group: 0
    - makedirs: True

elasticsearch_config:
  file.managed:
    - name: /opt/elasticsearch/{{ pillar['elasticsearch']['cluster'] }}/config/elasticsearch.yml
    - user: 1000
    - group: 0
    - mode: 644
    - contents: |
        {% for node_name, node_roles in pillar['elasticsearch']['nodes']['roles'].items() %}{% if grains['id'] == node_name %}node.roles: {{ node_roles }}{% endif %}{% endfor %}
        xpack.ml.enabled: false
        node.name: {{ grains['id'] }}
        cluster.name: {{ pillar['elasticsearch']['cluster'] }}
        discovery.seed_hosts: "{% for master in pillar['elasticsearch']['nodes']['master'] %}{% if master != grains['id'] %}{{ master }}:{{ pillar['elasticsearch']['ports']['transport'] }}{% if not loop.last %},{% endif %}{% endif %}{% endfor %}"
        cluster.initial_master_nodes: "{% for master in pillar['elasticsearch']['nodes']['master'] %}{{ master }}{% if not loop.last %},{% endif %}{% endfor %}"
        bootstrap.memory_lock: "true"
        network.host: 0.0.0.0
        network.publish_host: {{ pillar['elasticsearch']['nodes']['ips'][grains['id']] }}
        http.port: {{ pillar['elasticsearch']['ports']['http'] }}
        transport.port: {{ pillar['elasticsearch']['ports']['transport'] }}
        xpack.security.enabled: true
        xpack.security.transport.ssl.enabled: true
        xpack.security.transport.ssl.verification_mode: certificate
        xpack.security.transport.ssl.key: /usr/share/elasticsearch/config/certs/elasticsearch_{{ grains['id'] }}_key.key
        xpack.security.transport.ssl.certificate: /usr/share/elasticsearch/config/certs/elasticsearch_{{ grains['id'] }}_fullchain.cer
        xpack.security.transport.ssl.certificate_authorities: [ "/usr/share/elasticsearch/config/certs/elasticsearch_{{ grains['id'] }}_ca.cer" ]
        xpack.security.http.ssl.enabled: true
        xpack.security.http.ssl.verification_mode: certificate
        xpack.security.http.ssl.key: /usr/share/elasticsearch/config/certs/elasticsearch_{{ grains['id'] }}_key.key
        xpack.security.http.ssl.certificate: /usr/share/elasticsearch/config/certs/elasticsearch_{{ grains['id'] }}_fullchain.cer
        {{ pillar['elasticsearch']['config'] }}

elasticsearch_cert:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar['elasticsearch']['acme_account'] }}/verify_and_issue.sh elasticsearch {{ grains['id'] }}"

elasticsearch_image:
  cmd.run:
    - name: docker pull {{ pillar['elasticsearch']['image'] }}

elasticsearch_container:
  docker_container.running:
    - name: elasticsearch-{{ pillar['elasticsearch']['cluster'] }}
    - user: root
    - image: {{ pillar['elasticsearch']['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - 0.0.0.0:{{ pillar['elasticsearch']['ports']['http'] }}:{{ pillar['elasticsearch']['ports']['http'] }}/tcp
        - 0.0.0.0:{{ pillar['elasticsearch']['ports']['transport'] }}:{{ pillar['elasticsearch']['ports']['transport'] }}/tcp
    - binds:
        - /opt/elasticsearch/{{ pillar['elasticsearch']['cluster'] }}/config/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml
        - /opt/elasticsearch/{{ pillar['elasticsearch']['cluster'] }}/data:/usr/share/elasticsearch/data:rw
        - /opt/acme/cert:/usr/share/elasticsearch/config/certs:rw
    - watch:
        - /opt/elasticsearch/{{ pillar['elasticsearch']['cluster'] }}/config/elasticsearch.yml
    - environment:
        - ES_JAVA_OPTS: {{ pillar['elasticsearch']['java_opts'] }}
    - ulimits:
        - memlock=-1:-1
        - nofile=65535:65535
    - extra_hosts:
        {%- for node_name, node_ip in pillar['elasticsearch']['nodes']['ips'].items() %}
          {% if grains['id'] != node_name %}- {{ node_name }}:{{ node_ip }}{% endif %}
          {% if grains['id'] == node_name %}- {{ node_name }}:127.0.0.1{% endif %}
        {%- endfor %}
{% endif %}
