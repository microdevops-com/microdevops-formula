pkg:
  tz:
    when: 'PKG_PKG'
    states:
      - timezone.system:
          'Europe/Moscow':
            - utc: False
