# Production OpenBao installation runbook

This runbook describes the single-node production deployment implemented by
the `openbao` Salt formula. It was verified with OpenBao 2.6.1 on Debian 13,
integrated Raft storage, ACME TLS, Shamir seal, file audit logging, validated
local Raft snapshots, and remote rsnapshot backup.

The examples use these values:

```text
Salt target: vault1.microdevops.com
Public service: https://vault.microdevops.com
Raft data: /opt/openbao/data
Raft snapshots: /opt/openbao/snapshots
Snapshot token: /root/.bao-token
```

Replace the host and certificate paths when deploying another instance.

## Security boundaries

- Never commit the initial root token or Shamir shares to pillar, Git, a ticket,
  chat, CI output, or documentation.
- Store the administrator password and all recovery shares in the approved
  password manager. Storing all shares under one identity makes that identity
  the effective recovery boundary even when OpenBao uses a 5-of-3 threshold.
- `/root/.bao-token` is only the restricted Raft snapshot token. Do not put the
  root or administrator token there.
- A normal `bao login` can overwrite `/root/.bao-token`. Operator logins on this
  host must use `-no-store`.
- Do not use `openbao.root_token_file` for this production deployment.
- Do not apply `openbao.unseal` with shares in ordinary pillar. Unseal manually
  from the password manager.
- The live `/opt/openbao/data` directory is not the primary backup. Back up
  validated snapshots from `/opt/openbao/snapshots`.

## Repository preparation

The assembled Salt project needs all of the following before deployment:

1. The `microdevops-formula` submodule revision containing the `openbao`
   formula and Raft snapshot helper.
2. Formula wiring under `formulas/openbao` in the public project template.
3. A host top fragment assigning the client OpenBao pillar.
4. A client pillar with ACME, Raft, audit, telemetry, and snapshot settings.
5. An rsnapshot source for `/opt/openbao/snapshots` and an explicit suppression
   for live `/opt/openbao` coverage.

For the verified client, inspect these concrete paths:

```text
pillar/top_sls/vault1.microdevops.com
pillar/openbao/vault1_microdevops_com.sls
pillar/rsnapshot_backup/microdevops/backup.sls
formulas/microdevops-formula/openbao/
```

The production pillar must not contain `privileged_token`, `unseal_keys`,
`recovery_keys`, PostgreSQL storage, or static-seal configuration.

Validate all pillars before touching the host:

```bash
./.docker_run.sh /.check_pillar_for_roster.sh
```

## 1. Bootstrap the rebuilt host

Confirm the roster address and SSH host key first. From the assembled client
project, apply only the normal host bootstrap required by that project. Then
verify that the target is Debian 13 and that HTTPS port 443 is allowed by the
host firewall configuration.

For the verified `vault1.microdevops.com` rebuild, the controller sequence was:

```bash
./.docker_run.sh salt-ssh --wipe vault1.microdevops.com \
  state.apply bootstrap

./.docker_run.sh salt-ssh --wipe vault1.microdevops.com \
  state.highstate
```

Stop and resolve every failed state before installing OpenBao. Reconnect after
firewall or SSH changes and confirm Salt SSH still reaches the host.

The exact bootstrap state assignment is client-owned. Do not infer it from this
formula or apply an unrelated example blindly.

## 2. Compile before applying

Compile the OpenBao state without changing the host:

```bash
./.docker_run.sh salt-ssh --wipe vault1.microdevops.com \
  state.show_sls openbao.init
```

Review the compiled output for these requirements:

- the ACME state is included;
- certificate issuance precedes certificate permissions and validation;
- `openbao_service_enable_and_start` requires certificate validation;
- the listener uses the expected certificate and key paths;
- storage is `raft`, not PostgreSQL;
- no static seal is configured;
- `/opt/openbao/snapshot-raft.sh` is managed;
- snapshot cron is absent until the configured token file exists.

## 3. Install and configure OpenBao

Apply only the installation/configuration stage:

```bash
./.docker_run.sh salt-ssh --wipe vault1.microdevops.com \
  state.apply openbao.init
```

Verify on the host:

```bash
systemctl is-active openbao
systemctl status openbao --no-pager
bao version

export BAO_ADDR=https://vault.microdevops.com
export BAO_CACERT=/opt/acme/cert/openbao_vault.microdevops.com_fullchain.cer
bao status
```

Before initialization, `bao status` should report that the service is not
initialized. The certificate and key must exist, be non-empty, and be readable
by the `openbao` service account.

## 4. Initialize once

The client pillar selects normal Shamir initialization with five shares and a
threshold of three. Apply initialization exactly once:

```bash
./.docker_run.sh salt-ssh --wipe vault1.microdevops.com \
  state.apply openbao.initialization
```

`openbao.initialization` currently writes `/root/openbao-init.json` and emits a
pillar-shaped copy of the root token and shares in the Salt return. Treat the
entire command output as secret. Do not run it in CI or retain it in terminal
logging. This output behavior is a formula limitation, not a recommendation to
store the values in pillar.

On the host, copy the initial root token and all five shares directly into the
approved password-manager record. Verify the record before continuing. Do not
commit them anywhere.

## 5. Unseal manually

Enter three different shares interactively on the host:

```bash
export BAO_ADDR=https://vault.microdevops.com
export BAO_CACERT=/opt/acme/cert/openbao_vault.microdevops.com_fullchain.cer

bao operator unseal
bao operator unseal
bao operator unseal
bao status
```

Expected status includes:

```text
Initialized    true
Sealed         false
Storage Type   raft
```

## 6. Enable audit configuration

Apply the separate audit stage:

```bash
./.docker_run.sh salt-ssh --wipe vault1.microdevops.com \
  state.apply openbao.audit
```

Verify the file and configured device:

```bash
test -s /var/log/openbao_audit.log
systemctl is-active openbao
```

Authenticated `bao audit list` verification is performed after administrator
authentication is configured.

## 7. Create a non-root administrator

Create a password-manager Login for the OpenBao administrator before running
these commands. Authenticate temporarily with the initial root token:

```bash
export BAO_ADDR=https://vault.microdevops.com
export BAO_CACERT=/opt/acme/cert/openbao_vault.microdevops.com_fullchain.cer

read -rsp 'Initial root token: ' BAO_TOKEN
export BAO_TOKEN
echo

bao policy write admin - <<'EOF'
path "*" {
  capabilities = [
    "create", "read", "update", "patch",
    "delete", "list", "scan", "sudo"
  ]
}
EOF

bao auth enable userpass

read -rsp 'New admin password: ' ADMIN_PASSWORD
echo
printf '%s' "$ADMIN_PASSWORD" |
  bao write auth/userpass/users/admin password=- policies=admin
unset ADMIN_PASSWORD BAO_TOKEN
```

Test the login without writing a token helper file:

```bash
ADMIN_TOKEN="$(
  bao login -method=userpass -no-store -token-only username=admin
)"
export BAO_TOKEN="$ADMIN_TOKEN"

bao policy read admin
bao auth list
bao audit list

unset ADMIN_TOKEN BAO_TOKEN
```

Do not publish `bao token lookup` output: it contains the issued token ID.

## 8. Provision the restricted snapshot token

Authenticate as `admin` with `-no-store`, then create the minimal policy and a
renewable periodic orphan token:

```bash
ADMIN_TOKEN="$(
  bao login -method=userpass -no-store -token-only username=admin
)"
export BAO_TOKEN="$ADMIN_TOKEN"

bao policy write openbao-raft-snapshot - <<'EOF'
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF

umask 077
bao token create \
  -policy=openbao-raft-snapshot \
  -period=24h \
  -orphan \
  -no-default-policy \
  -display-name=openbao-raft-snapshot \
  -field=token > /root/.bao-token
chmod 0600 /root/.bao-token

unset ADMIN_TOKEN BAO_TOKEN
```

Reapply `openbao.init` after the non-empty token file exists. This enables the
otherwise-gated snapshot cron:

```bash
./.docker_run.sh salt-ssh --wipe vault1.microdevops.com \
  state.apply openbao.init
```

Verify the installed cron entry and run the first snapshot manually:

```bash
test -s /root/.bao-token
test "$(stat -c '%a' /root/.bao-token)" = 600
/opt/openbao/snapshot-raft.sh
ls -l /opt/openbao/snapshots
```

The helper renews its token, skips cleanly on a non-leader, writes to a
temporary directory, verifies the archive layout and embedded checksums,
renames the snapshot atomically, and performs retention only after success.

## 9. Verify remote backup

The rsnapshot configuration runs on the backup host, not on the OpenBao host.
For the verified deployment, run on `backup5.sysadm.ws`:

```bash
/opt/sysadmws/rsnapshot_backup/rsnapshot_backup.py \
  --sync --host vault1.microdevops.com

/opt/sysadmws/rsnapshot_backup/rsnapshot_backup.py \
  --check --host vault1.microdevops.com
```

Compare the newest local snapshot checksum with its remote copy under:

```text
/var/backups/microdevops/vault1.microdevops.com/.sync/rsnapshot/opt/openbao/snapshots/
```

The hashes must match. Do not treat live `/opt/openbao/data` copying as the
primary recovery mechanism.

## 10. Remove initialization material and revoke root

Only after all of the following are proven:

- five shares are present in the password manager;
- three shares successfully unseal the service;
- `admin` login has administrative access;
- a validated local snapshot exists;
- the remote snapshot checksum matches;

revoke the initial root token with itself:

```bash
read -rsp 'Initial root token: ' BAO_TOKEN
export BAO_TOKEN
echo
bao token revoke -self
unset BAO_TOKEN
```

After successful revocation, remove the obsolete initial root token from the
password-manager record. Keep the administrator credentials and current five
shares.

Remove the initialization file with the dedicated state:

```bash
./.docker_run.sh salt-ssh --wipe vault1.microdevops.com \
  state.apply openbao.remove_init_file
```

Verify:

```bash
test ! -e /root/openbao-init.json
```

The production pillar must still contain no root token or unseal shares.

## 11. Final acceptance checks

```bash
systemctl is-active openbao
bao status
test -s /opt/openbao/snapshots/"$(
  find /opt/openbao/snapshots -maxdepth 1 -type f \
    -name 'openbao_*.snap' -printf '%f\n' | sort | tail -1
)"
```

Confirm externally:

- `https://vault.microdevops.com` presents the expected ACME certificate;
- TCP 443 is reachable only as intended by UFW policy;
- audit logging continues after a test login;
- snapshot cron uses the configured four-hour schedule;
- the next scheduled snapshot and remote backup complete successfully;
- the initial root token no longer authenticates.

## Restart and recovery

After a restart, a Shamir-sealed instance starts sealed. An operator must enter
three different current shares:

```bash
export BAO_ADDR=https://vault.microdevops.com
export BAO_CACERT=/opt/acme/cert/openbao_vault.microdevops.com_fullchain.cer
bao operator unseal
bao operator unseal
bao operator unseal
bao status
```

Do not add shares to pillar to automate this step. Restoring a Raft snapshot is
a separate disaster-recovery operation and should first be rehearsed on an
isolated replacement host. Never test restoration against the production data
directory.
