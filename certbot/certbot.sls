{% if (pillar['certbot'] is defined) and (pillar['certbot'] is not none) %}
  {%- if (pillar['certbot']['enabled'] is defined) and (pillar['certbot']['enabled'] is not none) and (pillar['certbot']['enabled']) %}
certbot_deps:
  git.latest:
    - name: https://github.com/certbot/certbot
    - target: /opt/certbot
    - force_reset: True
    - force_fetch: True
  {%- endif %}
{% endif %}
