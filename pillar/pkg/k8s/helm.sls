pkg:
  k8s-helm:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - cmd.run:
          1:
            - name: 'rm -f /tmp/helm-v2.11.0-linux-amd64.tar.gz'
          2:
            - name: 'curl -L https://storage.googleapis.com/kubernetes-helm/helm-v2.11.0-linux-amd64.tar.gz -o /tmp/helm-v2.11.0-linux-amd64.tar.gz'
          3:
            - name: 'tar zxvf /tmp/helm-v2.11.0-linux-amd64.tar.gz --strip-components=1 -C /usr/local/bin linux-amd64/helm'
          4:
            - name: 'tar zxvf /tmp/helm-v2.11.0-linux-amd64.tar.gz --strip-components=1 -C /usr/local/bin linux-amd64/tiller'
          5:
            - name: 'chmod +x /usr/local/bin/helm'
          6:
            - name: 'chmod +x /usr/local/bin/tiller'
