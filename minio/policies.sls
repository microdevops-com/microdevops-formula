{% if pillar["minio"]["policies"] is defined %}
  {%- for policy in pillar["minio"]["policies"] %}
create_{{ policy["name"] }}.json:
  file.managed:
    - name: /opt/minio/policies/{{ policy["name"] }}.json
    - source: salt://minio/files/policy.jinja
    - template: jinja
    - mode: 0644
    - makedirs: True
    - context:
        statement: {{ policy["statement"] }}
{{ policy["name"] }}_add:
  cmd.run:
    - name: minio-client admin policy add local {{ policy["name"] }} /opt/minio/policies/{{ policy["name"] }}.json
  {%- endfor %}
{%- endif %}
