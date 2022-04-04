{%- if pillar["consul"] is defined %}
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
  file.serialize:
    - name: /opt/consul/{{ pillar["consul"]["name"] }}/config/config.json
    - dataset: {{ pillar["consul"]["config"] | json }}
    - formatter: json

{%-   if 'node_services' in pillar["consul"]  %}
{%-     for node in pillar["consul"]["node_services"] %}
{%-       if node["node_name"] == grains["fqdn"] %}
{%-         for service in node["services"] %}
consul serivce {{ service["config"]["service"]["name"] }} config on {{ node["node_name"] }}:
  file.serialize:
    - name: /opt/consul/{{ pillar["consul"]["name"] }}/config/{{ service["config"]["service"]["name"] }}.json
    - dataset: {{ service["config"] }}
    - formatter: json
{%-         endfor %}
{%-       endif %}
{%-     endfor %}
{%-   endif %}

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
      - 127.0.0.1:53:{{ pillar["consul"]["config"]["ports"]["dns"] }}/tcp
      - 0.0.0.0:8301:8301/udp
      - 0.0.0.0:8302:8302/udp
      - 127.0.0.1:53:{{ pillar["consul"]["config"]["ports"]["dns"] }}/udp
    - binds:
      - /opt/consul/{{ pillar["consul"]["name"] }}/config/:/consul/config:rw
      - /opt/consul/{{ pillar["consul"]["name"] }}/data/:/consul/data:rw
      - /opt/consul/{{ pillar["consul"]["name"] }}/logs/:/consul/logs:rw
      - /opt/consul/{{ pillar["consul"]["name"] }}/certs/:/consul/certs:rw
    - command: {{ pillar["consul"]["command"] }}
    - cap_add:
      - NET_BIND_SERVICE
    - environment:
        - CONSUL_ALLOW_PRIVILEGED_PORTS: yes
        - CONSUL_HTTP_ADDR: 'https://127.0.0.1:{{ pillar["consul"]["config"]["ports"]["https"] }}'
        - CONSUL_CACERT: /consul/certs/ca.crt
    {%- for key, val in pillar["consul"]["agents"]["clients"].items() %}{%- if grains['fqdn'] == key %}
        - CONSUL_CLIENT_CERT: /consul/certs/agent-client.crt
        - CONSUL_CLIENT_KEY: /consul/certs/agent-client.key{%- endif %}{%- endfor %}
    {%- for key, val in pillar["consul"]["agents"]["servers"].items() %}{%- if grains['fqdn'] == key %}
        - CONSUL_CLIENT_CERT: /consul/certs/{{ grains['fqdn'] }}.crt
        - CONSUL_CLIENT_KEY: /consul/certs/{{ grains['fqdn'] }}.key{%- endif %}{%- endfor %}

resolv_conf:
  file.replace:
    - name: /etc/resolv.conf
    - pattern: '^ *nameserver 127.0.0.53.*$'
    - repl: 'nameserver 127.0.0.53'
    - prepend_if_not_found: True

systemd-resolved_consul_conf:
  file.managed:
    - name: /etc/systemd/resolved.conf.d/consul.conf
    - makedirs: True
    - contents: |
        [Resolve]
        DNS=127.0.0.1
        DNSSEC=false
        Domains=~consul

systemd-resolved_restart:
  cmd.run:
    - name: systemctl restart systemd-resolved
    - onchanges:
      - file: /etc/systemd/resolved.conf.d/consul.conf

docker_container_restart:
  cmd.run:
    - name: docker restart consul-{{ pillar["consul"]["name"] }}
    - onchanges:
      - file: /opt/consul/{{ pillar["consul"]["name"] }}/config/config.json
{% endif %}
