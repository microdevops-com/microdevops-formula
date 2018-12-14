{#
This file should be included in pillar, which sets the following:
WIP

And then:
{% include 'pkg/k8s/rke_cluster.sls' with context %}
#}

pkg:
  k8s-rke_cluster:
    when: 'PKG_AFTER_DEPLOY'
    states:
      - file.line:
          1:
            - name: '/etc/rc.local'
            - mode: ensure
            - before: '^exit\ 0$'
            - content: 'mount --make-shared /'
      - cmd.run:
          1:
            - name: 'mount --make-shared /'
      - file.directory:
          1:
            - name: '/opt/rancher/clusters/{{ cluster_name }}'
            - mode: 755
            - makedirs: True
          2:
            - name: '/opt/rancher/clusters/{{ cluster_name }}/.ssh'
            - mode: 700
            - makedirs: True
      - file.managed:
          1:
            - name: '/opt/rancher/clusters/{{ cluster_name }}/.ssh/id_rsa'
            - mode: 0600
            - contents: {{ cluster_ssh_private_key | yaml_encode }}
          2:
            - name: '/opt/rancher/clusters/{{ cluster_name }}/.ssh/id_rsa.pub'
            - mode: 0644
            - contents: |
                {{ cluster_ssh_public_key }}
          3:  
            - name: '/opt/rancher/clusters/{{ cluster_name }}/cluster.yml'
            - mode: 0644
            - source: 'salt://pkg/files/k8s/rke_cluster/cluster.yml'
            - template: jinja
            - defaults:
                nodes: |
{% for node in nodes %}
                  - address: {{ node['address'] }}
                    port: "{{ node['port'] }}"
                    internal_address: {{ node['internal_address'] }}
                    role: {{ node['role'] }}
                    hostname_override: {{ node['address'] }}
                    user: {{ node['user'] }}
                    docker_socket: /var/run/docker.sock
                    ssh_key: ""
                    ssh_key_path: /opt/rancher/clusters/{{ cluster_name }}/.ssh/id_rsa
                    labels: {}
{% endfor %}
                cluster_ip_range: {{ cluster_ip_range }}
                cluster_cidr: {{ cluster_cidr }}
                cluster_domain: {{ cluster_domain }}
                cluster_dns_server: {{ cluster_dns_server }}
                cluster_name: {{ cluster_name }}
      - ssh_auth.present:
          1:
            - user: 'root'
            - names:
                - {{ cluster_ssh_public_key }}
{#
{% if grains['fqdn'] == rke_up_exec_host %}
      - cmd.run:
          1:
            - name: 'rke up --config /opt/rancher/clusters/{{ cluster_name }}/cluster.yml'
{% endif %}
#}
