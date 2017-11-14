{% if grains['os'] in ['Ubuntu', 'Debian'] %}
disable_auto_upgrades:
  file.managed:
    - name: '/etc/apt/apt.conf.d/20auto-upgrades'
    - source: salt://pkg/files/20auto-upgrades
    - mode: 0644
{% endif %}
