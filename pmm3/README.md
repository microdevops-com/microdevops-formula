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
- `GF_SERVER_DOMAIN` is always set to `pmm3:name`. PMM itself does not set the domain, so without it
  every link in an alert would point to `https://localhost/graph`.
- The certificate goes to `srv/nginx/certificate.{crt,key}`. PMM does not regenerate existing files.
  `cert-sync.sh` copies the renewed acme certificate there every day and reloads nginx.
- Do not run `pmm-admin config --force` / `pmm-agent setup --force` again on a registered agent: it re-creates
  the node, and PMM drops its services. `pmm3.agent` registers only an agent that is not yet connected.
