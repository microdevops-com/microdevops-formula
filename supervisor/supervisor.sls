{% if (pillar['supervisor'] is defined) and (pillar['supervisor'] is not none) %}
  {%- if (pillar['supervisor']['enabled'] is defined) and (pillar['supervisor']['enabled'] is not none) and (pillar['supervisor']['enabled']) %}
supervisor_install:
  pkg.installed:
    - pkgs:
      - supervisor
  {%- endif %}
{% endif %}
