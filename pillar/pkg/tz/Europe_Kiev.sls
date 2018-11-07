pkg:
  tz:
    when: 'PKG_PKG'
    states:
{% if grains['oscodename'] == 'jessie' %}
      - file.managed:
          1:
            - name: "/etc/timezone"
            - contents: |
                Europe/Kiev
      - cmd.run:
          1:
            - name: "dpkg-reconfigure -f noninteractive tzdata"
{% else %}
      - timezone.system:
          'Europe/Kiev':
            - utc: False
{% endif %}
