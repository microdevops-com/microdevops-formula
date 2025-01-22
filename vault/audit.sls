{% if pillar["vault"] is defined and pillar["vault"]["audit"] is defined  and pillar["vault"]["privileged_token"] is defined %}

{% set audit_logfile = pillar["vault"]["audit"]["logfile"] | default('/var/log/vault_audit.log') %}
{% set privileged_token = pillar["vault"]["privileged_token"] %}
{% set vault_addr = pillar["vault"]["env_vars"]["VAULT_ADDR"] %}

  {% if pillar["vault"]["audit"]["enable"] %}

vault audit file create:
  file.managed:
    - name: {{ audit_logfile }}
    - user: vault
    - group: vault
    - mode: 0640
    - makedirs: True

vault audit enable:
  cmd.run:
    - name: 'vault audit enable file file_path={{ audit_logfile }}'
    - env:
        VAULT_ADDR: {{ vault_addr }}
        VAULT_TOKEN: {{ privileged_token }}
        VAULT_SKIP_VERIFY: true
    - unless: 'vault audit list | grep -q file'
    - require:
      - file: vault audit file create

  {% else %}

vault audit disable check:
  cmd.run:
    - name: '[ -f "{{ audit_logfile }}" ] && vault audit list | grep -q file || echo "Condition failed"'
    - env:
        VAULT_ADDR: {{ vault_addr }}
        VAULT_TOKEN: {{ privileged_token }}
        VAULT_SKIP_VERIFY: true

vault audit disable:
  cmd.run:
    - name: 'vault audit disable file'
    - env:
        VAULT_ADDR: {{ vault_addr }}
        VAULT_TOKEN: {{ privileged_token }}
        VAULT_SKIP_VERIFY: true
    - onlyif: 'vault audit list | grep -q file'

  {% endif %}

{% endif %}
