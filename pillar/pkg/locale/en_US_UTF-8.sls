pkg:
  tz:
    when: 'PKG_PKG'
    states:
      - locale.present:
          1:
            - name: en_US.UTF-8
      - locale.system:
          1:
            - name: en_US.UTF-8
