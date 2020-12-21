{% if pillar["bootstrap"] is defined and "files" in pillar["bootstrap"] %}
  {%- if "managed" in pillar["bootstrap"]["files"] %}
    {%- for file in pillar["bootstrap"]["files"]["managed"] %}
      {%- do file["values"].update({'bootstrap_network_domain': pillar["bootstrap"]["network"]["domain"]}) %}
bootstrap_file_managed_{{ loop.index }}:
  file.managed:
    - name: {{ file["name"] }}
    - source: {{ file["source"] }}
    - mode: {{ file["mode"] }}
    - template: jinja
    - defaults: {{ file["values"] }}

      {%- if "apply" in file %}
        {%- set a_loop = loop %}
        {%- for cmd in file["apply"] %}
bootstrap_file_managed_run_{{ loop.index }}_{{ a_loop.index }}:
  cmd.run:
    - name: {{ cmd }}

        {%- endfor %}
      {%- endif %}
    {%- endfor %}
  {%- endif %}

  {%- if "absent" in pillar["bootstrap"]["files"] %}
    {%- for file in pillar["bootstrap"]["files"]["absent"] %}
bootstrap_file_absent_{{ loop.index }}:
    file.absent:
      - name: {{ file["name"] }}

    {%- endfor %}
  {%- endif %}
{% endif %}
