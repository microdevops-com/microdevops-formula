{% if pillar["vault"] is defined and pillar["vault"]["audit"] is defined and pillar["vault"]["audit"]["enable"] and pillar["vault"]["privileged_token"] is defined %}

{% set autid_logfile = pillar["vault"]["audit"]["logfile"] | default('/var/log/vault_audit.log') %}
{% set privileged_token = pillar["vault"]["privileged_token"] %}
{% set vault_addr = pillar["vault"]["env_vars"]["VAULT_ADDR"] %}

vault audit file create:
  file.managed:
    - name: {{ autid_logfile }}
    - user: vault
    - group: vault
    - mode: 0640
    - makedirs: True


vault audit enable:
  cmd.run:
    - name: 'vault audit enable file file_path={{ autid_logfile }}'
    - env:
        VAULT_ADDR: {{ vault_addr }}
        VAULT_TOKEN: {{ privileged_token }}
    - unless: 'vault audit list | grep -q file'
    - require:
      - file: vault audit file create

{% endif %}
