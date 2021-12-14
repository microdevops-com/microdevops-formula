{% if pillar["consul"] is defined %}
docker_install_00:
  file.directory:
    - name: /etc/docker
    - mode: 700

docker_install_01:
  file.managed:
    - name: /etc/docker/daemon.json
    - contents: |
        { "iptables": false, "default-address-pools": [ {"base": "172.16.0.0/12", "size": 24} ] }

docker_install_1:
  pkgrepo.managed:
    - humanname: Docker CE Repository
    - name: deb [arch=amd64] https://download.docker.com/linux/{{ grains["os"]|lower }} {{ grains["oscodename"] }} stable
    - file: /etc/apt/sources.list.d/docker-ce.list
    - key_url: https://download.docker.com/linux/{{ grains["os"]|lower }}/gpg

pkgs_install:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - docker-ce: "{{ pillar["consul"]["docker-ce_version"] }}*"
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
    - name: systemctl restart docker
    - onchanges:
        - file: /etc/docker/daemon.json

consul_data_dir:
  file.directory:
    - names:
      - /opt/consul/{{ pillar["consul"]["name"] }}/data
      - /opt/consul/{{ pillar["consul"]["name"] }}/config
      - /opt/consul/{{ pillar["consul"]["name"] }}/logs
      - /opt/consul/{{ pillar["consul"]["name"] }}/certs
    - mode: 755
    - user: 100 
    - group: 1000
    - makedirs: True

consul_config:
  file.managed:
    - name: /opt/consul/{{ pillar["consul"]["name"] }}/config/config.json
    - contents: |
        {{ pillar["consul"]["config"] | indent(8) }}

consul_config_2:
  file.replace:
    - name: /opt/consul/{{ pillar["consul"]["name"] }}/config/config.json
    - pattern: '(^ *"retry_join": \[.*), \],$'
    - repl: '\1],'

cacert:
  file.managed:
    - name: /opt/consul/{{ pillar["consul"]["name"] }}/certs/ca.crt
    - source: {{ pillar["consul"]["tls_dir"] }}/ca.crt
    - user: 100
    - group: 1000
{%- for key, val in pillar["consul"]["agents"]["servers"].items() %}{%- if grains['fqdn'] == key %}
server_cert:
  file.managed:
    - name: /opt/consul/{{ pillar["consul"]["name"] }}/certs/{{ grains['fqdn'] }}.crt
    - source: {{ pillar["consul"]["tls_dir"] }}/{{ grains['fqdn'] }}.crt
    - user: 100
    - group: 1000
server_key:
  file.managed:
    - name: /opt/consul/{{ pillar["consul"]["name"] }}/certs/{{ grains['fqdn'] }}.key
    - source: {{ pillar["consul"]["tls_dir"] }}/{{ grains['fqdn'] }}.key
    - user: 100
    - group: 1000
{%- endif %}{%- endfor %}
{%- for key, val in pillar["consul"]["agents"]["clients"].items() %}{%- if grains['fqdn'] == key %}
client_cert:
  file.managed:
    - name: /opt/consul/{{ pillar["consul"]["name"] }}/certs/agent-client.crt
    - source: {{ pillar["consul"]["tls_dir"] }}/agent-client.crt
    - user: 100
    - group: 1000
client_key:
  file.managed:
    - name: /opt/consul/{{ pillar["consul"]["name"] }}/certs/agent-client.key
    - source: {{ pillar["consul"]["tls_dir"] }}/agent-client.key
    - user: 100
    - group: 1000
{%- endif %}{%- endfor %}
consul_image:
  cmd.run:
    - name: docker pull {{ pillar["consul"]["image"] }}

consul_container:
  docker_container.running:
    - name: consul-{{ pillar["consul"]["name"] }}
    - user: root
    - image: {{ pillar["consul"]["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
      - 0.0.0.0:8300:8300/tcp
      - 0.0.0.0:8301:8301/tcp
      - 0.0.0.0:8302:8302/tcp
      - 0.0.0.0:8500:8500/tcp
      - 0.0.0.0:8501:8501/tcp
      - 0.0.0.0:8600:8600/tcp
      - 0.0.0.0:8301:8301/udp
      - 0.0.0.0:8302:8302/udp
      - 0.0.0.0:8600:8600/udp
    - binds:
      - /opt/consul/{{ pillar["consul"]["name"] }}/config/:/consul/config:rw
      - /opt/consul/{{ pillar["consul"]["name"] }}/data/:/consul/data:rw
      - /opt/consul/{{ pillar["consul"]["name"] }}/logs/:/consul/logs:rw
      - /opt/consul/{{ pillar["consul"]["name"] }}/certs/:/consul/certs:rw
    - command: {{ pillar["consul"]["command"] }}
    - environment:
        - CONSUL_HTTP_ADDR: 'https://127.0.0.1:8501'
        - CONSUL_CACERT: /consul/certs/ca.crt
    {%- for key, val in pillar["consul"]["agents"]["servers"].items() %}{%- if grains['fqdn'] == key %}
        - CONSUL_CLIENT_CERT: /consul/certs/agent-client.crt
        - CONSUL_CLIENT_KEY: /consul/certs/agent-client.key{%- endif %}{%- endfor %}
    {%- for key, val in pillar["consul"]["agents"]["clients"].items() %}{%- if grains['fqdn'] == key %}
        - CONSUL_CLIENT_CERT: /consul/certs/{{ grains['fqdn'] }}.crt
        - CONSUL_CLIENT_KEY: /consul/certs/{{ grains['fqdn'] }}.key{%- endif %}{%- endfor %}

docker_container_restart:
  cmd.run:
    - name: docker restart consul-{{ pillar["consul"]["name"] }}
    - onchanges:
      - file: /opt/consul/{{ pillar["consul"]["name"] }}/config/config.json
{% endif %}