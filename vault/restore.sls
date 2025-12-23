{%- if pillar["vault"] is defined and pillar["vault"].get("restore") is defined -%}

include:
  - vault.unseal

  {% set restore_snapshot = pillar["vault"]["restore"].get("snapshot_path") %}
  {% set vault_addr = pillar["vault"].get("env_vars", {}).get("VAULT_ADDR", "https://127.0.0.1:8200") %}
  {% set privileged_token = pillar["vault"].get("privileged_token") %}

vault_restore_pillar_missing:
  cmd.run:
    - name: |
        echo "ERROR: vault.restore requires 'snapshot_path' and 'privileged_token' in pillar.vault"
        exit 1
    - onlyif: test -z "{{ restore_snapshot }}" || test -z "{{ privileged_token }}"

  {%- if restore_snapshot and privileged_token %}

vault_restore_from_snapshot:
  cmd.run:
    - name: |
        vault operator raft snapshot restore -force {{ restore_snapshot }}
    - env:
      - VAULT_ADDR: "{{ vault_addr }}"
      - VAULT_SKIP_VERIFY: "true"
      - VAULT_TOKEN: "{{ privileged_token }}"

{%- set restore_unseal_keys = pillar['vault']['restore'].get('unseal_keys', []) %}

{%- if restore_unseal_keys %}
  {%- for key in restore_unseal_keys %}
vault restore unseal {{ loop.index }}:
  cmd.run:
    - name: |
        vault operator unseal {{ key }} || true
    - env:
      - VAULT_ADDR: "{{ vault_addr }}"
      - VAULT_SKIP_VERIFY: "true"
    - require:
      - cmd: vault_restore_from_snapshot
  {%- endfor %}
{%- endif %}

vault_restore_restart_service:
  service.running:
    - name: vault
    - enable: true
    - require:
      - cmd: vault_restore_from_snapshot
  {%- endif %}
{%- endif %}
