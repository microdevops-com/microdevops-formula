{% if pillar['rancher'] is defined and pillar['rancher'] is not none %}

  {%- if grains['fqdn'] in pillar['rancher']['nginx_hosts'] %}
nginx_deps:
  pkg.installed:
    - pkgs:
      - nginx

nginx_files_1:
  file.managed:
    - name: '/etc/nginx/nginx.conf'
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
        }

        stream {
            upstream rancher_servers {
                least_conn;
    {%- for node in pillar['rancher']['nodes'] %}
                server {{ node['internal_address'] }}:443 max_fails=3 fail_timeout=5s;
    {%- endfor %}
            }
            server {
                listen 443;
                proxy_pass rancher_servers;
            }
        } 

nginx_files_2:
  file.absent:
    - name: '/etc/nginx/sites-enabled/default'

nginx_reload:
  cmd.run:
    - runas: root
    - name: service nginx configtest && service nginx reload
  {%- endif %}

  # nodes and command_hosts
  {%- if grains['fqdn'] in pillar['rancher']['command_hosts'] or 'address', grains['fqdn'] in pillar['rancher']['nodes'] %}
kubectl_repo:
  pkgrepo.managed:
    - humanname: Kubernetes Repository
    - name: deb http://apt.kubernetes.io/ kubernetes-{{ 'xenial' if grains['oscodename'] == 'bionic' else grains['oscodename'] }} main
    - file: /etc/apt/sources.list.d/kubernetes.list
    - key_url: https://packages.cloud.google.com/apt/doc/apt-key.gpg
    - clean_file: True

kubectl_pkg:
  pkg.installed:
    - refresh: True
    - pkgs:
        - kubectl

rke_install_1:
  cmd.run:
    - name: 'curl -L https://github.com/rancher/rke/releases/download/v1.1.3/rke_linux-amd64 -o /usr/local/bin/rke'

rke_install_2:
  cmd.run:
    - name: 'chmod +x /usr/local/bin/rke'

helm_install_2:
  cmd.run:
    - name: 'curl -L https://get.helm.sh/helm-v3.2.4-linux-amd64.tar.gz -o /tmp/helm-v3.2.4-linux-amd64.tar.gz'

helm_install_3:
  cmd.run:
    - name: 'tar zxvf /tmp/helm-v3.2.4-linux-amd64.tar.gz --strip-components=1 -C /usr/local/bin linux-amd64/helm'

helm_install_5:
  cmd.run:
    - name: 'chmod +x /usr/local/bin/helm'

rancher_cli_install_2:
  cmd.run:
    - name: 'curl -L https://github.com/rancher/cli/releases/download/v2.4.5/rancher-linux-amd64-v2.4.5.tar.gz -o /tmp/rancher-linux-amd64-v2.4.5.tar.gz'

rancher_cli_install_3:
  cmd.run:
    - name: 'sudo tar zxvf /tmp/rancher-linux-amd64-v2.4.5.tar.gz --strip-components=2 -C /usr/local/bin ./rancher-v2.4.5/rancher'

rancher_cli_install_4:
  cmd.run:
    - name: 'chmod +x /usr/local/bin/rancher'

    {%- for node in pillar['rancher']['nodes'] %}
hosts_file_node_{{ loop.index }}:
  host.present:
    - ip: {{ node['internal_address'] }}
    - names:
        - {{ node['address'] }}
    {%- endfor %}

docker_install_1:
  pkgrepo.managed:
    - humanname: Docker CE Repository
    - name: deb [arch=amd64] https://download.docker.com/linux/ubuntu {{ grains['oscodename'] }} stable
    - file: /etc/apt/sources.list.d/docker-ce.list
    - key_url: https://download.docker.com/linux/ubuntu/gpg
    - clean_file: True

docker_install_2:
  pkg.installed:
    - refresh: True
    - pkgs:
        - docker-ce: '{{ pillar['rancher']['docker-ce_version'] }}*'
        - python-docker

docker_install_3:
  service.running:
    - name: docker

  {%- endif %}

  # command hosts only
  {%- if grains['fqdn'] in pillar['rancher']['command_hosts'] %}
cluster_dir_1:
  file.directory:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}'
    - mode: 755
    - makedirs: True

ssh_key_dir_2:
  file.directory:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/.ssh'
    - mode: 700
    - makedirs: True

ssh_key_file_1:
  file.managed:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/.ssh/id_rsa'
    - mode: 600
    - contents: {{ pillar['rancher']['cluster_ssh_private_key'] | yaml_encode }}

ssh_key_file_2:
  file.managed:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/.ssh/id_rsa.pub'
    - mode: 644
    - contents: |
        {{ pillar['rancher']['cluster_ssh_public_key'] }}

ssh_key_file_3:
  file.managed:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/cluster.yml'
    - mode: 644
    - source: 'salt://rancher/files/cluster.yml'
    - template: jinja
    - defaults:
        nodes: |
    {%- for node in pillar['rancher']['nodes'] %}
          - address: {{ node['address'] }}
            port: "{{ node['port'] }}"
            internal_address: {{ node['internal_address'] }}
            role: {{ node['role'] }}
            hostname_override: {{ node['address'] }}
            user: {{ node['user'] }}
            docker_socket: /var/run/docker.sock
            ssh_key: ""
            ssh_key_path: /opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/.ssh/id_rsa
            ssh_cert: ""
            ssh_cert_path: ""
            labels: {}
            taints: []
    {%- endfor %}
        cluster_ip_range: {{ pillar['rancher']['cluster_ip_range'] }}
        cluster_cidr: {{ pillar['rancher']['cluster_cidr']  }}
        cluster_domain: {{ pillar['rancher']['cluster_domain']  }}
        cluster_dns_server: {{ pillar['rancher']['cluster_dns_server']  }}
        cluster_name: {{ pillar['rancher']['cluster_name']  }}

ssh_key_file_4:
  file.managed:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kubectl.sh'
    - mode: 0755
    - contents: |
        #!/bin/bash
        kubectl --kubeconfig /opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kube_config_cluster.yml "$@"

ssh_key_file_5:
  file.managed:
    - name: '/opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/helm.sh'
    - mode: 0755
    - contents: |
        #!/bin/bash
        helm --kubeconfig /opt/rancher/clusters/{{ pillar['rancher']['cluster_name'] }}/kube_config_cluster.yml "$@"
  {%- endif %}

  # nodes only
  {%- if grains['fqdn'] in pillar['rancher']['command_hosts'] or 'address', grains['fqdn'] in pillar['rancher']['nodes'] %}
auth_file_from_cmd:
  ssh_auth.present:
    - user: 'root'
    - names:
        - {{ pillar['rancher']['cluster_ssh_public_key'] }}

docker_mount_1:
  file.managed:
    - name: '/etc/rc.local'
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
    - name: 'mount --make-shared /; ln -sf /dev/console /dev/kmsg'
  {%- endif %}

{% endif %}
