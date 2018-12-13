pkg:
  k8s-helm:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - cmd.run:
          1:
            - name: 'curl -L https://raw.githubusercontent.com/helm/helm/master/scripts/get -o /usr/local/bin/get_helm.sh'
          2:
            - name: 'chmod +x /usr/local/bin/get_helm.sh'
          3:
            - name: '/usr/local/bin/get_helm.sh'
