{% if pillar["minio"]["users"] is defined %}
  {%- for user in pillar["minio"]["users"] %}
create user {{ user["name"] }}:
  cmd.run:
    - name: minio-client admin user add local {{ user["name"] }} {{ user["password"] }}
    {% if "policies" in user %}
set policies for user {{ user["name"] }}:
  cmd.run:
    - name: minio-client admin policy set local {% for policy in user["policies"] -%} {{ policy }}{{ "," if not loop.last else "" }} {%- endfor %} user={{ user["name"] }}
    {%- endif %}
  {%- endfor %}
{%- endif %}
