{% if (pillar['redis'] is defined) and (pillar['redis'] is not none) %}
  {%- if (pillar['redis']['enabled'] is defined) and (pillar['redis']['enabled'] is not none) and (pillar['redis']['enabled']) %}
redis_deps:
  pkg.installed:
    - pkgs:
      - redis-server
      - redis-tools
  {%- endif %}
{% endif %}
