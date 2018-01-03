pkg:
  common:
    when: 'PKG_PKG'
    states:
      - pkg.installed:
          1:
            - pkgs:
                - virt-what
{%- if grains['os'] in ['Ubuntu', 'Debian'] %}
                - software-properties-common
      - file.managed:
          '/etc/apt/apt.conf.d/20auto-upgrades':
            - source: 'salt://pkg/files/20auto-upgrades'
            - mode: 0644
{%- endif %}
