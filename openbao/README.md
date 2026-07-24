# openbao Salt formula

Short documentation for this formula.

## Overview

This formula installs and configures OpenBao as a regular systemd service. It is modeled after the existing `vault` formula, but uses OpenBao package releases and the `bao` CLI.

Supported workflow:

- install OpenBao from an official GitHub release `.deb`
- manage `/etc/openbao/openbao.hcl` and `/etc/openbao/openbao.env`
- optionally install and initialize local PostgreSQL storage
- optionally create a self-signed TLS certificate
- optionally create a static seal key for auto-unseal
- initialize OpenBao and store init JSON
- manage audit logging
- write `/root/.bao-token` for root CLI usage
- create PostgreSQL database snapshots
- destructive wipe/reinstall workflow

## Files

- `init.sls` - install, config, TLS/static seal helpers, PostgreSQL setup, systemd service
- `initialization.sls` - runs `bao operator init`
- `unseal.sls` - unseal logic for non-auto-unseal deployments
- `audit.sls` - enable/disable file audit logging
- `root_token_file.sls` - creates `/root/.bao-token`
- `remove_init_file.sls` - removes init JSON after recovery material is stored safely
- `restore.sls` - restore PostgreSQL database dump
- `wipe.sls` - destructive wipe and reinstall
- `pillar.example` - single-node PostgreSQL storage example

## Basic Usage

Add an `openbao` pillar based on `openbao/pillar.example`, then apply:

```bash
salt-ssh 'target' state.apply openbao.init
salt-ssh 'target' state.apply openbao.initialization
```

`openbao.initialization` runs only when OpenBao is not initialized. It writes JSON to `/root/openbao-init.json` by default and prints a pillar-ready snippet containing `privileged_token` and `recovery_keys`.

With static seal or another auto-unseal mechanism, keep `init.use_recovery_keys: true`. For non-auto-unseal deployments, set `init.use_recovery_keys: false`; the state will use `key_shares`/`key_threshold` and print `unseal_keys`.

After storing the root token and recovery keys in a safe place, remove the temporary init file:

```bash
salt-ssh 'target' state.apply openbao.remove_init_file
```

## Install

By default the formula installs OpenBao `2.6.1` from:

```text
https://github.com/openbao/openbao/releases/download/v2.6.1/openbao_2.6.1_linux_amd64.deb
```

Override with:

```yaml
openbao:
  version: '2.6.1'
  package_url: 'https://example.com/openbao_2.6.1_linux_amd64.deb'
```

## PostgreSQL Storage

For local PostgreSQL managed by this formula:

```yaml
openbao:
  postgresql:
    install: true
    setup: true
    user: openbao
    database: openbao
    password: XXXXXXXXXXXXXXXXXXXXXXXX
```

The formula creates or updates the PostgreSQL user and creates the database if missing. The same password must be used in `openbao.config` inside the `storage "postgresql"` block.

## TLS

For lab use, a self-signed certificate can be generated:

```yaml
openbao:
  tls:
    self_signed:
      enable: true
      common_name: openbao.example.com
      subject_alt_name: "DNS:openbao.example.com,DNS:localhost,IP:127.0.0.1"
```

For production, prefer ACME/corporate CA and point `openbao.config` to the managed certificate/key paths.

## Static Seal

The lab-friendly static seal can be enabled:

```yaml
openbao:
  seal:
    static:
      enable: true
      key_file: /etc/openbao/seal/static-unseal.key
```

The state creates a 32-byte hex key without a newline using `openssl rand -hex 32`.

## Audit Logging

Add:

```yaml
openbao:
  audit:
    enable: true
    logfile: /var/log/openbao_audit.log
```

Apply:

```bash
salt-ssh 'target' state.apply openbao.audit
```

OpenBao 2.6 manages audit devices declaratively from server config. This state writes `/etc/openbao/audit.hcl` and reloads/restarts OpenBao; it does not call the audit API.

## Root Token File

After initialization, store the root token as `openbao.privileged_token` and apply:

```bash
salt-ssh 'target' state.apply openbao.root_token_file
```

This creates `/root/.bao-token` with mode `600`.

## Restore

For PostgreSQL dump restore:

```yaml
openbao:
  restore:
    snapshot_path: /opt/openbao/snapshots/openbao_26-07-24_12-00-00.sql
```

Apply:

```bash
salt-ssh 'target' state.apply openbao.restore
```

The restore state stops OpenBao, recreates the configured PostgreSQL database, loads the SQL dump, and starts OpenBao again.

## Diagnostics

```bash
bao version
systemctl status openbao --no-pager
bao status
curl --cacert /opt/openbao/tls/tls.crt https://127.0.0.1:8200/v1/sys/health | jq
cat /etc/openbao/openbao.hcl
cat /etc/openbao/openbao.env
```

With a root token:

```bash
export BAO_ADDR=https://127.0.0.1:8200
export BAO_CACERT=/opt/openbao/tls/tls.crt
export BAO_TOKEN="$(cat /root/.bao-token)"
bao audit list
bao secrets list
```

## Backup

Back up at least:

- OpenBao PostgreSQL database
- `/etc/openbao/openbao.hcl`
- `/etc/openbao/seal/static-unseal.key` if static seal is used
- root token and recovery material
- TLS certificate/key if they are not externally managed

If `openbao.snapshots.enable_postgresql` is true, the formula creates `/opt/openbao/snapshot-postgresql.sh` and schedules it via cron.
