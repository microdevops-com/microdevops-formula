{% if pillar["cloudflare"] is defined %}
requests_pip_installed:
  pip.installed:
    - name: requests
    - reload_modules: True

  {%- for zone_name, zone_data in pillar["cloudflare"].items()|sort %}
cloudflare_apply_{{ zone_name }}:
  cloudflare.manage_zone_records:
    - name: {{ zone_name }}
    - zone: {{ zone_data|yaml }}
  {%- endfor %}
{% endif %}
