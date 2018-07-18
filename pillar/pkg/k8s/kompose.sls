pkg:
  k8s-kompose:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - cmd.run:
          1:
            - name: 'curl -L https://github.com/kubernetes/kompose/releases/download/v1.15.0/kompose-linux-amd64 -o /usr/local/bin/kompose'
          2:
            - name: 'chmod +x /usr/local/bin/kompose'
