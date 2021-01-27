{% set helm_version = "v3.5.0" %}
pkg:
  k8s-helm:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - cmd.run:
          1:
            - name: 'rm -f /tmp/helm-{{ helm_version }}-linux-amd64.tar.gz'
          2:
            - name: 'curl -L https://get.helm.sh/helm-{{ helm_version }}-linux-amd64.tar.gz -o /tmp/helm-{{ helm_version }}-linux-amd64.tar.gz'
          3:
            - name: 'tar zxvf /tmp/helm-{{ helm_version }}-linux-amd64.tar.gz --strip-components=1 -C /usr/local/bin linux-amd64/helm'
          4:
            - name: 'chmod +x /usr/local/bin/helm'
