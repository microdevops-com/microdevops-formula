# Cloudflare Log Explorer collector

This formula installs a small, dependency-free collector for Cloudflare Log
Explorer. It stores selected `http_requests` and `firewall_events` fields as
local JSON Lines. It does not forward those logs anywhere.

## Cloudflare preparation

1. Enable the zone-level `http_requests` and `firewall_events` datasets in Log
   Explorer. Dataset changes require `Logs Edit`; the collector does not need
   that permission.
2. Create a separate API token with only **Zone / Logs Read**, restricted to
   the one required zone.
3. Put the token in the project's protected `cloudflare_log_collector.token`
   pillar. The formula writes the configured `token_file` as root-only mode
   `0600`; it is not included in the rendered-state context or file diffs.

If a Salt SDB secret provider is configured for the project, `token` may be an
SDB-resolved pillar value. It must never be placed in a public/shared formula
repository or printed in state output.

## Pillar

See `pillar.example`. `zone_id` is required. The default timer runs every five
minutes, queries only through two minutes before the current time to allow for
ingestion delay, and deliberately overlaps the previous two minutes.

The SQLite state in `/var/lib/cloudflare-log-collector/state.sqlite3` contains
per-dataset cursors and event hashes. An event is durably queued before it is
appended and the cursor moves only after a complete time slice succeeds.
Overlap is therefore safe and normal runs do not duplicate output. HTTP and
firewall collection fail independently.

The selected path field excludes the query string. Bodies, cookies, request
and response headers, and authorization data are never selected.

Output defaults to:

- `/var/log/cloudflare/http_requests.jsonl`
- `/var/log/cloudflare/firewall_events.jsonl`

Files rotate daily, retain 14 rotations, and are compressed after one cycle.

## Validation

Run formula tests with:

```sh
python3 -m unittest discover -s cloudflare_log_collector/tests -v
python3 -m py_compile cloudflare_log_collector/files/collector.py
```

After deployment, confirm the dataset schema and collection without printing
the token:

```sh
systemctl start cloudflare-log-collector.service
systemctl status cloudflare-log-collector.service --no-pager
journalctl -u cloudflare-log-collector.service --since '-15 minutes' --no-pager
tail -n 3 /var/log/cloudflare/http_requests.jsonl | jq -c .
tail -n 3 /var/log/cloudflare/firewall_events.jsonl | jq -c .
```

Generate an ordinary request to a proxied hostname and identify or generate a
harmless WAF event (for example, a temporary Cloudflare custom rule in Log
mode, approved by the zone operator). Wait one polling interval, then find the
corresponding Ray IDs in the two JSONL files. Run the service a second time and
confirm each Ray ID still has the same line count. Do not test by sending an
exploit payload to production.
