pkg:
  tz:
    when: 'PKG_PKG'
    states:
      - timezone.system:
          'Asia/Shanghai':
            - utc: False
