# vault Salt formula

Short, accurate documentation for this formula.

## Overview
This formula installs and configures HashiCorp Vault, supports:
- Binary installation (specified via `pillar['vault']['version']`) — downloads official Vault zip and installs `/usr/bin/vault`.
- APT installation (legacy) following HashiCorp apt repository instructions.
- Setting capabilities (`CAP_IPC_LOCK`, `CAP_NET_BIND_SERVICE`) so Vault can bind to privileged ports (443).
- Snapshot creation
- Restore from snapshot, initialization, unseal, and full wipe workflows.

## Files
- init.sls — install/config (binary and apt branches)
- initialization.sls — runs `vault operator init` and stores JSON on the Vault host
- unseal.sls — unseal logic using pillar['vault']['unseal_keys']
- audit.sls — enable/disable audit logging to file
- remove_init_files.sls — cleanup of init JSON files after keys are safely stored in pillar
- root_token_file.sls — create `/root/.vault-token` with root token for quick authentication
- restore.sls — restore snapshot workflow
- wipe.sls — destructive reinstall + wipe

## Pillar (example)
```
vault:
  version: '1.21.1'          # optional — if present, binary install is used
  privileged_token: '...'
  unseal_keys:
    - 'AAA...='
    - 'BBB...='
    - 'CCC...='
  env_vars:
    VAULT_ADDR: 'https://127.0.0.1:8200'
  init:
    key_shares: 5
    key_threshold: 3
    output_file: /opt/vault/init-temp.json
  restore:
    snapshot_path: /opt/vault/snapshots/vault_YY-MM-DD.snap
    unseal_keys:                  # optional: keys to use only for restore
      - 'ZZZ...='
```

## Key workflows

### Install
- With binary: set `vault.version` in pillar. The formula downloads the specified release zip from releases.hashicorp.com, extracts only the `vault` binary to `/usr/bin/vault`, sets perms and capabilities, and creates systemd unit.
- With apt: omit `vault.version`. The formula follows the official apt repo setup (signed-by keyring) and installs `vault` package.

### Initialization
- Prerequisite: apply `vault.init` first (installs binary/package, writes config/env, systemd unit, and starts the service).

```bash
salt-ssh 'target' state.apply vault.init
salt-ssh 'target' state.apply vault.initialization
```

- The `vault.initialization` state runs `vault operator init -format=json` only when Vault is not initialized. It saves JSON to `/opt/vault/init-temp.json`, and prints a pillar-ready YAML snippet to stdout so you can copy it into your pillar.

### Unseal
- `vault.unseal` reuses pillar['vault']['unseal_keys'].
- During restore, if `vault.restore.unseal_keys` is provided, those keys will be used for autounsealing restored storage.

### Restore (restore.sls)
- Requirements: `pillar['vault']['restore']['snapshot_path']` must be set.
- Behavior:
  - Includes `vault.unseal` so unseal states are available.
  - Stops/starts vault service appropriately, runs `vault operator raft snapshot restore` with provided `snapshot_path`.
  - After restore, it performs unseal steps using `vault.restore.unseal_keys`.
- Important: Vault must be reachable and the privileged token available in pillar for operations that require authentication.

### Wipe (wipe.sls)
- Stops Vault, deletes configured data path `/opt/vault/data`, removes package or binary depending on install mode, then includes `vault.init` and `vault.initialization` to reinstall and re-init.

### Audit Logging (audit.sls)
- Enable or disable audit logging via pillar:
  ```yaml
  vault:
    audit:
      enable: true
      file: /var/log/vault_audit.log
  ```
- Apply the state:
  ```bash
  salt-ssh 'target' state.apply vault.audit
  ```
- Requires `privileged_token` in pillar for authentication.
- Audit logs are written to the specified file in JSON format.

### Root Token File (root_token_file.sls)
- After initialization, store your `privileged_token` in pillar and apply:
  ```bash
  salt-ssh 'target' state.apply vault.root_token_file
  ```
- Creates `/root/.vault-token` with mode 600, allowing `root` to run Vault commands without manually providing `VAULT_TOKEN`:
  ```bash
  sudo vault status  # will automatically use /root/.vault-token
  ```

### Cleanup Init Files (remove_init_files.sls)
- After safely copying the JSON output from `vault.initialization` into your pillar, remove the temporary init file:
  ```bash
  salt-ssh 'target' state.apply vault.remove_init_files
  ```
- Deletes `/opt/vault/init-temp.json` by default (configurable via `init.output_file`).
- Recommended: do this only after you have verified the keys are stored in a safe location (pillar, sealed backup, etc.).

## Systemd & capabilities
- The formula always creates `/etc/systemd/system/vault.service.d/capabilities.conf` with:
  ```
  [Service]
  CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK CAP_NET_BIND_SERVICE
  AmbientCapabilities=CAP_NET_BIND_SERVICE
  ```
- The Vault binary receives capabilities via `setcap` so binding to port 443 works on both install methods.

## Quick Diagnostics Commands

### Vault Status & Health
```bash
# Check Vault status (sealed/unsealed, cluster info)
vault status

# Check if Vault is initialized
vault status -format=json | jq -r '.initialized'

# Check if Vault is sealed
vault status -format=json | jq -r '.sealed'

# Health check endpoint
curl -k https://localhost:8200/v1/sys/health

# Leader status
curl -sk https://localhost:8200/v1/sys/leader | jq
```

### Raft Cluster
```bash
# List Raft peers
vault operator raft list-peers

# Show cluster configuration
vault read sys/storage/raft/configuration

# Check if node is leader
vault read sys/leader
```

### Snapshots
```bash
# List snapshots directory
ls -lah /opt/vault/snapshots/

# Verify snapshot integrity
vault operator raft snapshot inspect /opt/vault/snapshots/vault_latest.snap

# Manually create snapshot
vault operator raft snapshot save /tmp/manual-backup.snap
```

### Configuration & Environment
```bash
# Check Vault config file
cat /etc/vault.d/vault.hcl

# Verify environment variables
cat /etc/vault.d/vault.env

# Check if VAULT_ADDR is set in current shell
echo $VAULT_ADDR

# Test network connectivity to Vault
curl -k -I -L https://localhost:8200
```

### TLS Certificates
```bash
# Test TLS connection
openssl s_client -connect localhost:8200 -showcerts
```

### Audit & Logs
```bash
# Check audit device status
vault audit list

# View audit log (if file backend enabled)
tail -f /var/log/vault_audit.log | jq
```

### Authentication & Tokens
```bash
# Login with root token
vault login

# Check token info
vault token lookup

# Renew current token
vault token renew

# List token accessors
vault list auth/token/accessors
```

### Secrets Engines
```bash
# List enabled secrets engines
vault secrets list

# Check secrets engines
vault secrets list -detailed 
```

### Performance & Metrics
```bash
# Prometheus metrics endpoint (if enabled)
curl -sk https://localhost:8200/v1/sys/metrics?format=prometheus
```

