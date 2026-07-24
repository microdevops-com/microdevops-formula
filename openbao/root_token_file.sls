{% if pillar["openbao"] is defined and pillar["openbao"].get("privileged_token") is defined %}

openbao_root_token_file:
  file.managed:
    - name: /root/.bao-token
    - mode: 600
    - user: root
    - group: root
    - contents: |
        {{ pillar["openbao"]["privileged_token"] | indent(8) }}

{% endif %}
