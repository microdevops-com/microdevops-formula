{% if pillar["rancher"] is defined %}
  {%- for rancher_key, rancher_val in pillar["rancher"].items() %}
    {%- if "run" in rancher_val and rancher_val["run"] %}
      {%- set node_list = [] %}
      {%- for node in rancher_val["nodes"] %}
        {%- do node_list.append(node["address"]) %}
      {%- endfor %}

      # nginx hosts only
      {%- if grains["id"] in rancher_val["nginx_hosts"] %}
nginx_deps:
  pkg.latest:
    - refresh: True
    - pkgs:
      - nginx

nginx_files_1:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - contents: |
        worker_processes 4;
        worker_rlimit_nofile 40000;
        load_module /usr/lib/nginx/modules/ngx_stream_module.so;

        events {
            worker_connections 8192;
        }

        http {
            server {
                listen 80;
                return 301 https://$host$request_uri;
            }
        }

        stream {
            upstream rancher_servers {
                least_conn;
    {%- for node in rancher_val["nodes"] %}
                server {{ node["internal_address"] }}:443 max_fails=3 fail_timeout=5s;
    {%- endfor %}
            }
            server {
                listen 443;
                proxy_pass rancher_servers;
            }
        } 

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

nginx_reload:
  cmd.run:
    - runas: root
    - name: service nginx configtest && service nginx reload
      {%- endif %}

      # nodes and command_hosts
      {%- if grains["id"] in rancher_val["command_hosts"] or grains["id"] in node_list %}
kubectl_repo:
  pkgrepo.managed:
    - humanname: Kubernetes Repository
    - name: deb http://apt.kubernetes.io/ kubernetes-{{ "xenial" if grains["oscodename"] in ["bionic", "focal", "jammy"] else grains["oscodename"] }} main
    - file: /etc/apt/sources.list.d/kubernetes.list
    - key_url: https://packages.cloud.google.com/apt/doc/apt-key.gpg
    - clean_file: True

kubectl_pkg:
  pkg.latest:
    - refresh: True
    - pkgs:
        - kubectl

rke_install_1:
  cmd.run:
    - name: curl -L https://github.com/rancher/rke/releases/download/{{ rancher_val["rke_version"] }}/rke_linux-amd64 -o /usr/local/bin/rke

rke_install_2:
  cmd.run:
    - name: chmod +x /usr/local/bin/rke

helm_install_1:
  cmd.run:
    - name: curl -L https://get.helm.sh/helm-{{ rancher_val["helm_version"] }}-linux-amd64.tar.gz -o /tmp/helm-{{ rancher_val["helm_version"] }}-linux-amd64.tar.gz

helm_install_2:
  cmd.run:
    - name: tar zxvf /tmp/helm-{{ rancher_val["helm_version"] }}-linux-amd64.tar.gz --strip-components=1 -C /usr/local/bin linux-amd64/helm

helm_install_3:
  cmd.run:
    - name: chmod +x /usr/local/bin/helm

rancher_cli_install_1:
  cmd.run:
    - name: curl -L https://github.com/rancher/cli/releases/download/{{ rancher_val["rancher_cli_version"] }}/rancher-linux-amd64-{{ rancher_val["rancher_cli_version"] }}.tar.gz -o /tmp/rancher-linux-amd64-{{ rancher_val["rancher_cli_version"] }}.tar.gz

rancher_cli_install_2:
  cmd.run:
    - name: sudo tar zxvf /tmp/rancher-linux-amd64-{{ rancher_val["rancher_cli_version"] }}.tar.gz --strip-components=2 -C /usr/local/bin ./rancher-{{ rancher_val["rancher_cli_version"] }}/rancher

rancher_cli_install_3:
  cmd.run:
    - name: chmod +x /usr/local/bin/rancher

      {%- endif %}

      # command hosts only
      {%- if grains["id"] in rancher_val["command_hosts"] %}
cluster_dir:
  file.directory:
    - name: /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}
    - mode: 755
    - makedirs: True

ssh_key_dir:
  file.directory:
    - name: /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/.ssh
    - mode: 700
    - makedirs: True

ssh_key_file_1:
  file.managed:
    - name: /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/.ssh/id_ed25519
    - mode: 600
    - contents: {{ rancher_val["cluster_ssh_private_key"] | yaml_encode }}

ssh_key_file_2:
  file.managed:
    - name: /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/.ssh/id_ed25519.pub
    - mode: 644
    - contents: |
        {{ rancher_val["cluster_ssh_public_key"] }}

cluster_file_1:
  file.managed:
    - name: /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/cluster.yml
    - mode: 644
    - source: salt://rancher/files/{{ rancher_val["cluster_yml"] }}
    - template: jinja
    - defaults:
        nodes: |
        {%- for node in rancher_val["nodes"] %}
          - address: {{ node["address"] }}
            port: "{{ node["port"] }}"
            internal_address: {{ node["internal_address"] }}
            role: {{ node["role"] }}
            hostname_override: {{ node["address"] }}
            user: {{ node["user"] }}
            docker_socket: /var/run/docker.sock
            ssh_key: ""
            ssh_key_path: /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/.ssh/id_ed25519
            ssh_cert: ""
            ssh_cert_path: ""
            labels: {{ node["labels"] }}
            taints: {{ node["taints"] }}
        {%- endfor %}
        cluster_ip_range: {{ rancher_val["cluster_ip_range"] }}
        cluster_cidr: {{ rancher_val["cluster_cidr"]  }}
        cluster_domain: {{ rancher_val["cluster_domain"]  }}
        cluster_dns_server: {{ rancher_val["cluster_dns_server"]  }}
        cluster_name: {{ rancher_val["cluster_name"]  }}
        node_max_pods: {{ rancher_val["node_max_pods"] }}
        ingress_node_selector: {{ rancher_val["ingress_node_selector"] }}
        monitoring_node_selector: {{ rancher_val["monitoring_node_selector"] }}
        network: {{ rancher_val["network"] }}

cluster_file_2:
  file.managed:
    - name: /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/kubectl.sh
    - mode: 0755
    - contents: |
        #!/bin/bash
        kubectl --kubeconfig /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/kube_config_cluster.yml "$@"

cluster_file_3:
  file.managed:
    - name: /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/helm.sh
    - mode: 0755
    - contents: |
        #!/bin/bash
        helm --kubeconfig /opt/rancher/clusters/{{ rancher_val["cluster_name"] }}/kube_config_cluster.yml "$@"
      {%- endif %}

      # nodes only
      {%- if grains["id"] in node_list %}
        {%- for node in rancher_val["nodes"] %}
hosts_file_node_{{ loop.index }}:
  host.present:
    - ip: {{ node["internal_address"] }}
    - names:
        - {{ node["address"] }}
        {%- endfor %}

auth_file_from_cmd:
  ssh_auth.present:
    - user: root
    - names:
        - {{ rancher_val["cluster_ssh_public_key"] }}

docker_install_1:
  pkgrepo.managed:
    - humanname: Docker CE Repository
    - name: deb [arch=amd64] https://download.docker.com/linux/ubuntu {{ grains["oscodename"] }} stable
    - file: /etc/apt/sources.list.d/docker-ce.list
    - key_url: https://download.docker.com/linux/ubuntu/gpg
    - clean_file: True

docker_install_2:
  pkg.installed:
    - refresh: True
    - pkgs:
        - docker-ce: {{ rancher_val["docker-ce_version"] }}*
        {%- if grains["oscodename"] in ["focal", "jammy"] %}
        - python3-docker
        {%- else %}
        - python-docker
        {%- endif %}

docker_install_3:
  service.running:
    - name: docker

docker_mount_1:
  file.managed:
    - name: /etc/rc.local
    - user: root
    - group: root
    - mode: 0755
    - contents: |
        #!/bin/bash
        mount --make-shared /
        ln -sf /dev/console /dev/kmsg
        exit 0

docker_mount_2:
  cmd.run:
    - name: mount --make-shared /; ln -sf /dev/console /dev/kmsg

      {%- endif %}
    {%- endif %}
  {%- endfor %}
{% endif %}
