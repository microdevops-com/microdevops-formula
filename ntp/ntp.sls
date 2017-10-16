{% if (grains['virtual_subtype'] is not defined) or (grains['virtual_subtype'] != 'LXC') %}
  {%- if (grains['virtual'] is not defined) or (grains['virtual'] != 'LXC') %}

ntp_service_installed:
  pkg.installed:
    - pkgs:
      - ntp

ntp_service_running:
  service.running:
    {% if grains['os'] in ['CentOS', 'RedHat'] %}
    - name: ntpd
    {% else %}
    - name: ntp
    {% endif %}
    - enable: True

  {%- endif %}
{% endif %}
