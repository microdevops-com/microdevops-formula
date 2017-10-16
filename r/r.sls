{% if (pillar['r'] is defined) and (pillar['r'] is not none) %}
  {%- if (pillar['r']['enabled'] is defined) and (pillar['r']['enabled'] is not none) and (pillar['r']['enabled']) %}
r_deps:
  pkg.installed:
    - pkgs:
      - r-base
  {%- endif %}
{% endif %}
