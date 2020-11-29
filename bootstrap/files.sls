{% if pillar["bootstrap"] is defined and "files" in pillar["bootstrap"] %}
  {%- for file in pillar["bootstrap"]["files" %}
    {%- do file["values"].update({'bootstrap_network_domain': pillar["bootstrap"]["network"]["domain"]}) %}
bootstrap_file_{{ loop.index }}:
  file.managed:
    - name: {{ file["name"] }}
    - source: {{ file["source"] }}
    - mode: {{ file["mode"] }}
    - template: jinja
    - defaults: 
        bootstrap_network_domain: {{ file["values"] }}

  {%- endfor %}
{% endif %}
