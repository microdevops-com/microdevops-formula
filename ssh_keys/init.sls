{% if pillar["ssh_keys"] is defined %}
  {%- for user, keys in pillar["ssh_keys"].items() %}
    {%- set i_loop = loop %}

    {%- if "present" in keys %}
      {%- for key in keys["present"] %}
ssh_keys_present_{{ i_loop.index }}_{{ loop.index }}:
  ssh_auth.present:
    - user: {{ user }}
    - name: {{ key }}

      {%- endfor %}
    {%- endif %}

    {%- if "absent" in keys %}
      {%- for key in keys["absent"] %}
ssh_keys_absent_{{ i_loop.index }}_{{ loop.index }}:
  ssh_auth.absent:
    - user: {{ user }}
    - name: {{ key }}

      {%- endfor %}
    {%- endif %}

  {%- endfor %}
{% endif %}
