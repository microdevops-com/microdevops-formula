{% if grains['os'] in ['Ubuntu', 'Debian'] and not grains['oscodename'] in ['karmic'] %}
pkg:
  common:
    when: 'PKG_PKG'
    states:
      - pkg.installed:
          1:
            - pkgs:
                - virt-what
                - software-properties-common
      - file.managed:
          '/etc/apt/apt.conf.d/20auto-upgrades':
            - source: 'salt://pkg/files/20auto-upgrades'
            - mode: 0644
{% endif %}
