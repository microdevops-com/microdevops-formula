{% if (pillar['pkg'] is defined) and (pillar['pkg'] is not none) %}
  {%- if (pillar['pkg']['common'] is defined) and (pillar['pkg']['common'] is not none) and (pillar['pkg']['common']) %}
pkg_common_installed:
  pkg.installed:
    - pkgs:
    {%- if grains['os'] in ['Ubuntu', 'Debian'] %}
      - software-properties-common
    {%- endif %}
      - virt-what
  {%- endif %}
{% endif %}
