pkg:
  k8s-kubeadm-kubelet-kubectl:
    when: 'PKG_BEFORE_DEPLOY'
    states:
      - pkgrepo.managed:
          1:
            - humanname: Kubernetes Repository
            - name: deb http://apt.kubernetes.io/ kubernetes-{{ grains['oscodename'] }} main
            - file: /etc/apt/sources.list.d/kubernetes.list
            - key_url: https://packages.cloud.google.com/apt/doc/apt-key.gpg
      - pkg.installed:
          1:
            - refresh: True
            - pkgs:
              - kubelet
              - kubeadm
              - kubectl
      - service.dead:
          1:
            - name: kubelet
      - file.replace:
          1:  
            - name: '/etc/systemd/system/kubelet.service.d/10-kubeadm.conf'
            - pattern: '^Environment="KUBELET_CERTIFICATE_ARGS=--rotate-certificates=true --cert-dir=/var/lib/kubelet/pki"$'
            - repl: 'Environment="KUBELET_CERTIFICATE_ARGS=--rotate-certificates=true --cert-dir=/var/lib/kubelet/pki --cgroup-driver=cgroupfs"'
      - cmd.run:
          1:
            - name: 'systemctl daemon-reload'
      - service.running:
          1:
            - name: kubelet
