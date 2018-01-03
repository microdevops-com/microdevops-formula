pkg:
  tz:
    when: 'PKG_PKG'
    states:
      - timezone.system:
          'Europe/Kiev':
            - utc: False
