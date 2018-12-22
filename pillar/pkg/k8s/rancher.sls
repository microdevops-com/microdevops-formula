pkg:
  k8s-rancher:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - cmd.run:
          1:
            - name: 'rm -f /tmp/rancher-linux-amd64-v2.0.6.tar.gz'
          2:
            - name: 'curl -L https://github.com/rancher/cli/releases/download/v2.0.6/rancher-linux-amd64-v2.0.6.tar.gz -o /tmp/rancher-linux-amd64-v2.0.6.tar.gz'
          3:
            - name: 'tar zxvf /tmp/rancher-linux-amd64-v2.0.6.tar.gz --strip-components=1 -C /usr/local/bin rancher-v2.0.6/rancher'
          4:
            - name: 'chmod +x /usr/local/bin/rancher'
