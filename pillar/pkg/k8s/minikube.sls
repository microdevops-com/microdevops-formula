pkg:
  k8s-minikube:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - cmd.run:
          1:
            - name: 'curl -L https://github.com/kubernetes/minikube/releases/download/v0.28.1/minikube-linux-amd64 -o /usr/local/bin/minikube'
          2:
            - name: 'chmod +x /usr/local/bin/minikube'
