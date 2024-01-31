{% if pillar['loki'] is defined and pillar['loki'] is not none %}

  {%- if pillar["docker-ce"] is not defined %}
    {%- set docker_ce = {"version": "latest",
                         "daemon_json": '{ "iptables": false, "default-address-pools": [ {"base": "172.16.0.0/12", "size": 24} ] }'} %}
  {%- endif %}
  {%- include "docker-ce/docker-ce.sls" with context %}

  {% if pillar["loki"].get("nginx_reverse_proxy", true) %}
    {% include "loki/nginx/nginx.sls" with context %}
  {% endif %}

loki_data_dir:
  file.directory:
    - names:
      - /opt/loki/{{ pillar['loki']['name'] }}
    - mode: 755
    - user: 0
    - group: 0
    - makedirs: True

loki_config:
  file.serialize:
    - name: /opt/loki/{{ pillar['loki']['name'] }}/config.yaml
    - user: 0
    - group: 0
    - mode: 644
    - serializer: yaml
    - dataset_pillar: loki:config
    - serializer_opts:
      - sort_keys: False
 
loki_image:
  cmd.run:
    - name: docker pull {{ pillar['loki']['image'] }}

loki_container:
  docker_container.running:
    - name: loki-{{ pillar['loki']['name'] }}
    - user: root
    - image: {{ pillar['loki']['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - 127.0.0.1:{{ pillar['loki']['config']['server']['http_listen_port'] }}:{{ pillar['loki']['config']['server']['http_listen_port'] }}/tcp
    - binds:
        - /opt/loki/{{ pillar['loki']['name'] }}:{{ pillar['loki']['path_prefix'] }}
    - watch:
        - /opt/loki/{{ pillar['loki']['name'] }}/config.yaml
    - command: -config.file={{ pillar['loki']['path_prefix'] }}/config.yaml

{% endif %}
