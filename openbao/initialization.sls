{% if pillar["openbao"] is defined %}

{% set init_cfg = pillar["openbao"].get("init", {}) %}
{% set use_recovery_keys = init_cfg.get("use_recovery_keys", True) %}
{% set key_shares = init_cfg.get("key_shares", 5) %}
{% set key_threshold = init_cfg.get("key_threshold", 3) %}
{% set recovery_shares = init_cfg.get("recovery_shares", 1) %}
{% set recovery_threshold = init_cfg.get("recovery_threshold", 1) %}
{% set init_file = init_cfg.get("output_file", "/root/openbao-init.json") %}
{% set bao_addr = pillar["openbao"].get("env_vars", {}).get("BAO_ADDR", "https://127.0.0.1:8200") %}
{% set bao_cacert = pillar["openbao"].get("env_vars", {}).get("BAO_CACERT", "/opt/openbao/tls/tls.crt") %}

openbao_operator_init:
  cmd.run:
{% if use_recovery_keys %}
    - name: bao operator init -recovery-shares={{ recovery_shares }} -recovery-threshold={{ recovery_threshold }} -format=json > {{ init_file }}
{% else %}
    - name: bao operator init -key-shares={{ key_shares }} -key-threshold={{ key_threshold }} -format=json > {{ init_file }}
{% endif %}
    - unless: bao status -format=json 2>/dev/null | jq -e '.initialized == true'
    - env:
      - BAO_ADDR: "{{ bao_addr }}"
      - BAO_CACERT: "{{ bao_cacert }}"
    - shell: /bin/bash

openbao_init_file_permissions:
  cmd.run:
    - name: chmod 0600 {{ init_file }} && chown root:root {{ init_file }}
    - onlyif: test -f {{ init_file }}
    - require:
      - cmd: openbao_operator_init

openbao_init_show:
  cmd.run:
    - name: |
        python3 << 'EOF'
        import json

        with open('{{ init_file }}', 'r') as f:
            init_data = json.load(f)

        root_token = init_data.get('root_token', '')
        recovery_keys = init_data.get('recovery_keys_b64', [])
        unseal_keys = init_data.get('unseal_keys_b64', [])

        print("\n" + "="*60)
        print("ADD THIS TO YOUR OPENBAO PILLAR:")
        print("="*60)
        print("openbao:")
        print("  privileged_token: '{}'".format(root_token))
        if recovery_keys:
            print("  recovery_keys:")
            for key in recovery_keys:
                print("    - '{}'".format(key))
        if unseal_keys:
            print("  unseal_keys:")
            for key in unseal_keys:
                print("    - '{}'".format(key))
        print("="*60)
        EOF
    - onlyif: test -f {{ init_file }}
    - require:
      - cmd: openbao_init_file_permissions

{% endif %}
