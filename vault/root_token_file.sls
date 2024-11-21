{% if pillar["vault"]["privileged_token"] is defined %}

vault_root_token_file:
  file.managed:
    - name: /root/.vault-token
    - mode: 600
    - user: root
    - group: root
    - contents: |
        {{ pillar["vault"]["privileged_token"] | indent(8) }}

{% endif %}
