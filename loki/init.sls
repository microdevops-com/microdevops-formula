{% if pillar['loki'] is defined and pillar['loki'] is not none %}
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
        - docker-ce: '{{ pillar['loki']['docker-ce_version'] }}*'
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

loki_data_dir:
  file.directory:
    - names:
      - name: /opt/loki/{{ pillar['loki']['name'] }}/config
      - name: /opt/loki/{{ pillar['loki']['name'] }}/chunks
      - name: /opt/loki/{{ pillar['loki']['name'] }}/wal
      - name: /opt/loki/{{ pillar['loki']['name'] }}/boltdb-shipper-active
      - name: /opt/loki/{{ pillar['loki']['name'] }}/boltdb-shipper-cache
      - name: /opt/loki/{{ pillar['loki']['name'] }}/boltdb-shipper-compactor
      - name: /opt/loki/{{ pillar['loki']['name'] }}/rules
      - name: /opt/loki/{{ pillar['loki']['name'] }}/rules-temp
      - name: /opt/loki/{{ pillar['loki']['name'] }}/
      
    - mode: 755
    - user: 1000
    - group: 0
    - makedirs: True

loki_config:
  file.managed:
    - name: /opt/loki/{{ pillar['loki']['name'] }}/config/config.yaml
    #- source: https://raw.githubusercontent.com/grafana/loki/v2.3.0/cmd/loki/loki-local-config.yaml
    #- source_hash: d4d430ebd8aa53b67a750140c4a2a2a5
    - user: 1000
    - group: 0
    - mode: 644
    - contents: |
        auth_enabled: false
        server:
          http_listen_port: {{ pillar['loki']['port'] }}
          grpc_listen_port: 9096
        ingester:
          wal:
            enabled: true
            dir: /tmp/wal
          lifecycler:
            address: 127.0.0.1
            ring:
              kvstore:
                store: inmemory
              replication_factor: 1
            final_sleep: 0s
          chunk_idle_period: 1h       # Any chunk not receiving new logs in this time will be flushed
          max_chunk_age: 1h           # All chunks will be flushed when they hit this age, default is 1h
          chunk_target_size: 1048576  # Loki will attempt to build chunks up to 1.5MB, flushing first if chunk_idle_period or max_chunk_age is reached first
          chunk_retain_period: 30s    # Must be greater than index read cache TTL if using an index cache (Default index read cache TTL is 5m)
          max_transfer_retries: 0     # Chunk transfers disabled
        schema_config:
          configs:
            - from: 2020-10-24
              store: boltdb-shipper
              object_store: filesystem
              schema: v11
              index:
                prefix: index_
                period: 24h
        storage_config:
          boltdb_shipper:
            active_index_directory: /tmp/loki/boltdb-shipper-active
            cache_location: /tmp/loki/boltdb-shipper-cache
            cache_ttl: 24h         # Can be increased for faster performance over longer query periods, uses more disk space
            shared_store: filesystem
          filesystem:
            directory: /tmp/loki/chunks
        compactor:
          working_directory: /tmp/loki/boltdb-shipper-compactor
          shared_store: filesystem
        limits_config:
          reject_old_samples: true
          reject_old_samples_max_age: 168h
        chunk_store_config:
          max_look_back_period: 0s
        table_manager:
          retention_deletes_enabled: false
          retention_period: 0s
        ruler:
          storage:
            type: local
            local:
              directory: /tmp/loki/rules
          rule_path: /tmp/loki/rules-temp
          alertmanager_url: http://localhost:9093
          ring:
            kvstore:
              store: inmemory
          enable_api: true
 
{#
loki_cert:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar['loki']['acme_account'] }}/verify_and_issue.sh loki {{ pillar['loki']['name'] }}"
#}
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
        - 0.0.0.0:{{ pillar['loki']['port'] }}:{{ pillar['loki']['port'] }}/tcp
    - binds:
        - /opt/loki/{{ pillar['loki']['name'] }}/config/config.yaml:/etc/loki/config.yaml
        - /opt/loki/{{ pillar['loki']['name'] }}/chunks:/tmp/loki/chunks
        - /opt/loki/{{ pillar['loki']['name'] }}/rules:/tmp/loki/rules
        - /opt/loki/{{ pillar['loki']['name'] }}/rules-temp:/tmp/loki/rules-temp
        - /opt/loki/{{ pillar['loki']['name'] }}/wal:/tmp/wal
        - /opt/loki/{{ pillar['loki']['name'] }}/boltdb-shipper-active:/tmp/loki/boltdb-shipper-active
        - /opt/loki/{{ pillar['loki']['name'] }}/boltdb-shipper-cache:/tmp/loki/boltdb-shipper-cache
        - /opt/loki/{{ pillar['loki']['name'] }}/boltdb-shipper-compactor:/tmp/loki/boltdb-shipper-compactor
    - watch:
        - /opt/loki/{{ pillar['loki']['name'] }}/config/config.yaml
    - command: -config.file=/etc/loki/config.yaml
{% endif %}
