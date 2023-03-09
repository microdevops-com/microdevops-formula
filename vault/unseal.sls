{% if pillar["vault"] is defined and pillar["vault"]["unseal_keys"] is defined %}

{% set vault_addr = pillar["vault"]["env_vars"]["VAULT_ADDR"] %}

  {% for key in pillar["vault"]["unseal_keys"] %}
vault unseal {{ loop.index }}:
  cmd.run:
    - name: vault operator unseal {{ key }}
    - shell: /bin/bash
    - env:
        VAULT_ADDR: {{ vault_addr }}
    - onlyif: 'vault status | grep "Sealed" | grep -q "true"'
  {% endfor %}

{% endif %}
