{% if pillar['vault'] is defined %}

{% set vault_version = pillar['vault'].get('version', None) %}
{% set use_binary = vault_version is not none %}
{% set default_paths = ['/vault/data', '/opt/vault/data', '/var/lib/vault'] %}
{% set wipe_paths = pillar['vault'].get('wipe', {}).get('paths', default_paths) %}

# Stop vault service
vault_wipe_stop:
  service.dead:
    - name: vault

# Remove storage/raft directories
{% for p in wipe_paths %}
vault_remove_path_{{ loop.index }}:
  cmd.run:
    - name: rm -rf {{ p }}
    - onlyif: test -e {{ p }}
    - require:
      - service: vault_wipe_stop
    - require_in:
      - user: vault_user
{% endfor %}

# Remove binary or purge package depending on install method
{% if use_binary %}
vault_remove_binary:
  file.absent:
    - name: /usr/bin/vault
    - require:
      - service: vault_wipe_stop
    - require_in:
      - user: vault_user
{% else %}
vault_purge_package:
  pkg.purged:
    - name: vault
    - require:
      - service: vault_wipe_stop
    - require_in:
      - user: vault_user
{% endif %}

# Include vault init and initialization states
include:
  - vault.init
  - vault.initialization

{% endif %}
