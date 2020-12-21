{% set rancher_version = "v2.4.9" %}
pkg:
  k8s-rancher:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - cmd.run:
          1:
            - name: 'rm -f /tmp/rancher-linux-amd64-{{ rancher_version }}.tar.gz'
          2:
            - name: 'curl -L https://github.com/rancher/cli/releases/download/{{ rancher_version }}/rancher-linux-amd64-{{ rancher_version }}.tar.gz -o /tmp/rancher-linux-amd64-{{ rancher_version }}.tar.gz'
          3:
            - name: 'sudo tar zxvf /tmp/rancher-linux-amd64-{{ rancher_version }}.tar.gz --strip-components=2 -C /usr/local/bin ./rancher-{{ rancher_version }}/rancher'
          4:
            - name: 'chmod +x /usr/local/bin/rancher'
