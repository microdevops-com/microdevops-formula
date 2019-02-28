pkg:
  k8s-rke:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - cmd.run:
          1:
            - name: 'curl -L https://github.com/rancher/rke/releases/download/v0.1.13/rke_linux-amd64 -o /usr/local/bin/rke'
          2:
            - name: 'chmod +x /usr/local/bin/rke'
