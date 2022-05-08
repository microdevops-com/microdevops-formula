pkg:
  k8s-kubectl:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - pkgrepo.managed:
          1:
            - humanname: Kubernetes Repository
            - name: deb http://apt.kubernetes.io/ kubernetes-{{ "xenial" if grains["oscodename"] in ["bionic", "focal", "jammy"] else grains["oscodename"] }} main
            - file: /etc/apt/sources.list.d/kubernetes.list
            - key_url: https://packages.cloud.google.com/apt/doc/apt-key.gpg
            - clean_file: True
      - pkg.installed:
          1:
            - refresh: True
            - pkgs:
              - kubectl
