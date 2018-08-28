pkg:
  sysdig:
    when: 'PKG_PKG'
    states:
      - pkgrepo.managed:
          1:
            - humanname: Draios Sysdig Repository
            - name: 'deb http://download.draios.com/stable/deb stable-$(ARCH)/'
            - file: /etc/apt/sources.list.d/draios.list
            - key_url: https://s3.amazonaws.com/download.draios.com/DRAIOS-GPG-KEY.public
      - pkg.latest:
          1:
            - refresh: True
            - pkgs:
              - sysdig
