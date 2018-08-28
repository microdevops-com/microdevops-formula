pkg:
  tz:
    when: 'PKG_PKG'
    states:
      - timezone.system:
          'Etc/UTC':
            - utc: True
