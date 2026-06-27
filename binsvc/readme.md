# binsvc

Run N independent instances of a statically-built binary
(VictoriaMetrics, VictoriaLogs, Grafana, Loki, Prometheus, Promtail,
exporters, ...) under systemd on the same host - each with its own install
dir, user, config, and (optionally) nginx vhost.

This is a fresh, opinionated state, not a refactor of the existing
`exporter`/`victoriametrics`/`application` formulas - those remain in
production use untouched. The patterns proven here (preset/instance merge,
building-block dispatch, a plain-Python logic layer split out from the
Salt-directive layer) are also a deliberate trial run for a possible future
rewrite of `application` into a general-purpose app-management state.

## Usage

```bash
salt 'minion-id' state.apply binsvc
salt 'minion-id' state.apply binsvc test=True
```

See `pillar.example` for the full pillar shape, available placeholders, and
worked examples (a minimal instance, two independent instances of the same
preset side by side, a direct-URL fetch, Grafana from its standalone tarball,
and a no-preset custom instance).

## How an instance is resolved

For every entry under `binsvc:instances`:

1. **Merge**: `defaults.yaml` -> `presets/<preset>.yaml` (deep-merged with any
   `binsvc:presets:<preset>` pillar override) -> the instance's own pillar.
   Later layers win; dicts merge recursively, everything else (including
   lists) is replaced wholesale - **except `svc.args`**, which is re-merged
   by flag name (`merge_args` in `lib.py`) right after. Mapping entries render
   as `{args_prefix}key=value`; string entries inside an args list render
   literally, so value-less flags like `--livereload` can be mixed in. A
   top-level raw string `svc.args` is still a complete args line and replaces
   the previous layer wholesale.
   `init.sls` does this for all instances first so consumers can gather merged
   producer stanzas from the same host.
2. **Resolve version/source**: `svc.version_resolver` selects resolver logic
   for the app. The default `github` resolver turns `version: latest` into a
   concrete GitHub release tag using `/releases/latest` (NOT `/tags` - the
   tags endpoint isn't sorted by date/semver and can return tags that were
   never published as releases). `github_versionsort` instead lists GitHub
   releases and picks the highest semver-like tag, for repos whose
   `/releases/latest` can point at an LTS branch. The `grafana` resolver uses
   Grafana's API to resolve both latest/concrete versions and the real package
   URL, because Grafana archive names contain build IDs that are not derivable
   from the version alone.
3. **Expand placeholders**, in two passes (`expand` in `lib.py`):
   - *Phase 1* against grain-derived identity (`osarch`, `kernel_lower`,
     `cpuarch`, `grain_id` = the minion id) plus the instance's own static keys
     (`name`, `type`, `version`, `tag`, `tag_vstrip`) and any operator-defined
     `binsvc:globals` (literal `{key}` values shared by all instances; a key
     clashing with a reserved one fails loud) - enough to resolve `install_dir`,
     `svc.source`, `svc.exec`, etc.
   - *Phase 2* adds `install_dir`, `exec`, `args` (top-level raw string, or args
     list joined from `{args_prefix}key=value` mappings and literal string
     tokens; default prefix `-`), `user_name`,
     `user_group` - keys only knowable once phase 1 has run - so e.g.
     `systemd.Service.ExecStart: "{exec} {args}"` just works, without resorting
     to fragile nested-placeholder syntax like `{svc[exec]}`.
4. **Dispatch** the building blocks that apply, in a fixed order:
   `user_ssh` -> `config_file` -> `fetch_archive` -> `commands(pre)` ->
   `systemd_unit` -> `commands(post)` -> `nginx_vhost`.
   An optional `binsvc:filter` (usually typed on the CLI, e.g.
   `pillar='{binsvc: {filter: "name: vm* *gra*; preset: exporter*"}}'`) scopes
   the apply to a subset: semicolon-separated `name`/`preset` glob clauses, union
   semantics. It gates dispatch only - step 1 still merges every instance, so a
   selected vmagent gathers all exporters' scrape jobs - while unselected
   instances skip resolve/expand entirely. Manual scoping, not change detection:
   a new exporter's job reaches vmagent only when vmagent is also in scope.
   `fetch_archive` and `config_file` each return the list of pyobjects requisite
   references that mean "the binary/config changed"; `dispatch`
   threads that list into `systemd_unit`'s `watch`, so the service restarts
   exactly when it needs to - without any block hardcoding another block's
   state IDs.

Before dispatch, an instance with `scrape_collect` gathers literal scrape jobs
from all merged instances with a matching `scrape.vmagent` selector and appends
them to the configured colon path, for example
`config:promscrape.yml:contents:scrape_configs`. This is host-local by design:
producers declare `scrape: {vmagent: <glob-or-list>, config: [...]}`, consumers
opt in with `scrape_collect`, and duplicate `job_name` values fail the render.

## Building blocks (`blocks/*.sls`)

| block | settings key | does |
|---|---|---|
| `fetch_archive` | `svc` | download an archive or bare binary, optionally `tar`-extract and/or `move` it into `install_dir`, ensure it's executable; make any `svc.data_dirs` service-user-owned for writable state (program files stay root-owned). Re-extract is guarded by an optional `svc.version_check` `unless` command — **no default**, so without it the archive re-extracts (and the service restarts) every run |
| `user_ssh` | `user`, `ssh` | system user/group + `.ssh` (keys, authorized_keys, config, known_hosts) - no-op unless `user.manage` |
| `config_file` | `config` | render named config file(s) from `contents` using optional `format: yaml\|ini\|json` (default yaml), or `source`+`template` |
| `commands` | `commands` | run ordered one-shot commands; `phase: pre\|post` controls before/after service start (default post), `when_set` gates on an optional input, `stdin` supports secrets |
| `systemd_unit` | `systemd` | render the unit from `systemd.{Unit,Service,Install}`, enable & (re)start it, restart on `watch` changes |
| `nginx_vhost` | `nginx` | reverse-proxy vhost (one upstream, `servers[]` blocks, optional per-server TLS + shared basic auth) - no-op unless `nginx.manage` |

`svc`/`systemd`/`nginx`/`config`/`commands`/`user`/`ssh` are all optional; an instance
that doesn't set a block's key simply skips it.

`nginx.servers[]` entries declare `names` and exactly one TLS source:
`acme_account`, `ssl_cert`+`ssl_key`, or neither. `acme_account` issues DNS ACME
certs through the separately managed `acme` state/pillar; binsvc derives the
`/opt/acme/cert/<vhost>_<first-name>_*` paths and does not manage accounts.

## The `lib.py` layer

`lib.py` is a plain, normally-importable Python file with **zero Salt
directives** — pure functions over plain dicts (placeholder expansion,
deep-merge, GitHub release resolution, archive/command helpers,
Grafana package resolution, systemd unit rendering). Unit-tested with plain pytest (`tests/test_lib.py`,
run via `python -m pytest tests/`), no minion required.

`init.sls` loads it with a single `from salt://binsvc/lib.py import ...`
line — the same `from salt://...import` mechanism used for block files, no
hardcoded path or `sys.path` manipulation needed. Because pyobjects gives each
block file a frozen snapshot of `_globals` at exec time (before `init.sls`'s
own body runs), lib functions are NOT automatically in block `__globals__`.
Blocks that need helpers therefore import them in their own source with a
top-level `from salt://binsvc/lib.py import ...` line, so pyobjects populates
that block's globals during the block import itself.

## Presets (`presets/*.yaml`)

Bundled, ready-to-use type configs (`vlserver`, `vlagent`, `vmserver`,
`vmagent`, `vmauth`, `exporter_node`, `grafana`) loaded lazily and cached per Salt run, deep-merged with optional
`binsvc:presets:<name>` pillar overrides - so instances only need to specify
what differs from the bundled defaults (typically just `install_dir`, `user`,
`svc.version`, and `nginx`).

`presets/generic.yaml` is a safe, mostly-commented reference preset documenting
the full current feature surface: fetch/version resolution, config rendering,
commands syntax, systemd, nginx, user/SSH, and placeholder behavior.
