{% if pillar["asterisk"]["state"] is defined %}
{%- for state_name, state_data in pillar["asterisk"]["state"].items() %}
{{state_name}}: {{ state_data }}
{%- endfor %}
{%- endif %}