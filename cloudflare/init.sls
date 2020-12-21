{% if pillar["cloudflare"] is defined %}
  {%- for zone_name, zone_data in pillar["cloudflare"].items()|sort %}
cloudflare_apply_{{ zone_name }}:
  cloudflare.manage_zone_records:
    - name: {{ zone_name }}
    - zone: {{ zone_data|yaml }}
  {%- endfor %}
{% endif %}
