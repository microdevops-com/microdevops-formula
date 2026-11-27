# pmm3

Percona Monitoring and Management 3 in Docker, with alerts managed from pillar.

| State | What it does |
| --- | --- |
| `pmm3` | `pmm3.server` + `pmm3.alerting` |
| `pmm3.server` | docker network, `pmm3-server` (`percona/pmm-server`), `pmm3-renderer` (grafana-image-renderer), admin password, acme certificate |
| `pmm3.alerting` | alert dashboards, Grafana alert rules, contact point and policy (file provisioning), `pmm3-telegram-relay` |
| `pmm3.agent` | `pmm-client` v3 on the host, registration, MySQL / HAProxy / MongoDB services |

Pillar: `pillar.example` (server) and `agent_pillar.example` (agent).

## Alerting

Alerts are Grafana Unified Alerting rules, generated from `pmm3:dashboards:dashboard_definitions`
together with `catalog.jinja`:

- one dashboard per definition, with the panels, styles and layout from the catalog;
- one rule per alert and subject (a node, or a PXC cluster), with the PromQL, threshold, reducer, window,
  frequency and pending period from the catalog, overridable per definition (`panel_*` context keys);
- each rule refers to its panel (`__dashboardUid__`, `__panelId__`).

The catalog has three levels:

- `alerts` - the alert registry, by key. The key is part of the rule uid and of its `panel_<key>_*` overrides;
- `sections` - dashboard rows, a title and a list of alerts. A section can be off by default; the definition
  turns it on or off with `section_<section>_enable`;
- `kinds` - the definition `template`: the subject, the grid and the sections. A kind `extends` other kinds and gets
  their sections first: `mysql` is `node` plus the MySQL sections.

| Kind | Subject | Sections |
| --- | --- | --- |
| `node` | `node_name` | `disk_memory`, `cpu` |
| `mysql` | `node_name` | `node` + `mysql`, `mysql_replication` (off by default) |
| `pxc_cluster` | `wsrep_cluster_name` | `pxc` |

The uids come from the kind's `uid_ns` and the subject, not from the kind name. The kinds of one subject share
`uid_ns`: there is one dashboard per subject, and a node moved from `node` to `mysql` keeps the rules of its node alerts.
`node` keeps the former kind name `disk_memory_cpu_mysql-replica` as `uid_ns`, and `pxc_cluster` keeps `pxc_size`,
so the rules created before the split kept their uids. The former template names and context keys
(`is_mysql_server`, `panel_mysql_replication_enable`) fail the render with a hint.

Grafana file provisioning creates and updates rules, but never deletes one that left the file. After a successful
reload the generated rule uids are saved in `<provisioning_path>/alert-rule-uids.applied`. The previous rules (that set,
and the rules in `salt-rules.yaml` on the host before it is rewritten) that are no longer generated (a removed
definition, a turned-off section) go to `salt-rules-delete.yaml` (`deleteRules`), and Grafana deletes them on the
reload. `test=True` shows them in the diff of that file. Rules from other provisioning files are never in the set.
A failed reload keeps the old set, so the deletion is retried on the next run. The first run of this version has no
`.applied` yet and takes the previous rules from `salt-rules.yaml`.

Notifications go through a webhook to `pmm3-telegram-relay` (`files/telegram-relay/relay.py`, stdlib only).
The relay renders the alert panel through the Grafana `/render` API and sends one Telegram post: the image,
with the alert text as its caption. Grafana's built-in Telegram integration sends the text and the image as
two separate posts.

Grafana file provisioning adds and updates by uid, but never deletes. When you rename a contact point
receiver uid, also list the old uid in `deleteContactPoints`. Otherwise the old receiver keeps sending,
and every notification arrives twice.

## Notes

- PMM 3 listens on 8443 inside the container and is published as `443:8443`. Agents connect to `<name>:443`.
- The container runs as uid 1000, gid 0. Everything under `srv/` must stay owned by uid 1000.
- Docker older than 20.10.10: its default seccomp profile breaks process spawning in the PMM 3 image (Oracle Linux 9
  glibc). The first start fails in initdb with `could not execute command "postgres" -V: Cannot allocate memory`.
  Upgrade Docker, or set `pmm3:security_opt: [seccomp=unconfined]`. The relay image (Debian glibc) fails the same way
  (`RuntimeError: can't start new thread`): `pmm3:alerting:telegram_relay:security_opt: [seccomp=unconfined]`.
  The renderer too: chromium fails with `posix_spawn ... chrome_crashpad_handler: Operation not permitted`, alert images
  are missing (render 500): `pmm3:renderer:security_opt: [seccomp=unconfined]`.
- `GF_SERVER_DOMAIN` is always set to `pmm3:name`. PMM itself does not set the domain, so without it
  every link in an alert would point to `https://localhost/graph`.
- The certificate goes to `srv/nginx/certificate.{crt,key}`. PMM does not regenerate existing files.
  `cert-sync.sh` copies the renewed acme certificate there every day and reloads nginx.
- Do not run `pmm-admin config --force` / `pmm-agent setup --force` again on a registered agent: it re-creates
  the node, and PMM drops its services. `pmm3.agent` registers only an agent that is not yet registered to
  `pmm_host:pmm_port` (checked in `/usr/local/percona/pmm/config/pmm-agent.yaml`, not by `Connected`).
- A changed `pmm3_agent:services:mysql:password` re-creates the PMM MySQL service (`pmm-admin remove` + `add`) with
  the same name. The MongoDB password is not managed: after changing it, run `pmm-admin remove mongodb <node_name>-mongodb`
  and apply `pmm3.agent` again.
- Services are registered as `<node_name>-mysql` and `<node_name>-mongodb`, and found by that name. With `node_name`
  set, a former registration of the same instance - the `pmm-admin` default name `<os hostname>-<type>` at the same
  address (MySQL - the socket, MongoDB - `host:port`) - is removed after the service is added under the new name.
  `pmm-admin add` checks the connection, so a failed add (an outdated password) leaves the former one collecting.
  Services with other names or at other addresses are not touched.
- MongoDB defaults are those of the former formula: `user: mongoadmin`, `query_source: profiler`. Set `user: pmm` and
  the query source explicitly (`agent_pillar.example`).
- `pmm3.agent` does not create the MongoDB user. Create it before the first apply: user `pmm` in `admin`, with the roles `pmmMonitor`
  (custom role: `find`, `dbHash`, `listIndexes`, `listCollections`, `collStats`, `dbStats`, `indexStats` on all
  collections, plus `system.version` and `system.profile`), `read@local` (oplog metrics), `clusterMonitor`, and on
  MongoDB 8.0+ `directShardOperations`. On a replica set, create it on the primary only.
- MongoDB `query_source`: `none` (metrics only), `mongolog` (QAN from the slow operations in the mongod log,
  MongoDB 5.0+, the log must be a file readable by pmm-agent and rotated with `copytruncate`), `profiler` (default, QAN from
  `system.profile`, the profiler must be enabled in mongod). Changing it, `user`, `host` or `port` of a registered service:
  `pmm-admin remove mongodb <node_name>-mongodb` and apply again.
