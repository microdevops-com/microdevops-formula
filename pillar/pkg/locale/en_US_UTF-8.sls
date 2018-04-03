pkg:
  locale:
    when: 'PKG_PKG'
    states:
      - locale.present:
          1:
            - name: "en_US.UTF-8 UTF-8"
      - cmd.run:
          1:
            - name: "/usr/sbin/update-locale LANG=en_US.UTF-8"
