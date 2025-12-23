{% if pillar['vault'] is defined %}

{% set init_cfg = pillar['vault'].get('init', {}) %}
{% set key_shares = init_cfg.get('key_shares', 5) %}
{% set key_threshold = init_cfg.get('key_threshold', 3) %}
{% set init_file = init_cfg.get('output_file', '/opt/vault/init-temp.json') %}
{% set vault_addr = pillar['vault'].get('env_vars', {}).get('VAULT_ADDR', 'https://127.0.0.1:8200') %}

# Run vault operator init and save JSON to disk (only if vault is not initialized)
vault_operator_init:
  cmd.run:
    - name: vault operator init -key-shares={{ key_shares }} -key-threshold={{ key_threshold }} -format=json > {{ init_file }}
    - onlyif: test "$(vault status -format=json 2>/dev/null | jq -r '.initialized // false')" = "false"
    - env:
      - VAULT_ADDR: "{{ vault_addr }}"
      - VAULT_SKIP_VERIFY: "true"
    - shell: /bin/bash

# Ensure file ownership is vault:vault so it's accessible for later
vault_init_chown:
  cmd.run:
    - name: chown vault:vault {{ init_file }} || true
    - onlyif: test -f {{ init_file }}
    - require:
      - cmd: vault_operator_init

# Print the pillar-formatted output so operator sees keys on console
vault_init_show:
  cmd.run:
    - name: |
        python3 << 'EOF'
        import json
        
        # Read the init JSON
        with open('{{ init_file }}', 'r') as f:
            init_data = json.load(f)
        
        root_token = init_data.get('root_token', '')
        unseal_keys = init_data.get('unseal_keys_b64', [])
        
        # Output as YAML with proper formatting
        print("\n" + "="*60)
        print("ADD THIS TO YOUR VAULT PILLAR:")
        print("="*60)
        print("vault:")
        print("  privileged_token: '{}'".format(root_token))
        print("  unseal_keys:")
        for key in unseal_keys:
            print("    - '{}'".format(key))
        print("="*60)
        EOF
    - onlyif: test -f {{ init_file }}
    - require:
      - cmd: vault_init_chown

{% endif %}
