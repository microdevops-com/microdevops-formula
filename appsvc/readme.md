# appsvc

Run N independent instances of a service or application on the same host -
each with its own install dir, user, config, and (optionally) nginx vhost.
Today: statically-built binaries (VictoriaMetrics, VictoriaLogs, Grafana,
Loki, Prometheus, exporters, ...) and Python daemons in a managed venv under
systemd. In progress: multi-runtime web apps (php-fpm pools, node/python
runtimes, git sources, docker) - see TODO.md item 18.

Formerly `binsvc`.

This is a fresh, opinionated state, not a refactor of the existing
`exporter`/`victoriametrics`/`app` formulas - those remain in production use
untouched. It is deliberately portable: it does not include or depend on
other formulas in this repository.

## Usage

```bash
salt 'minion-id' state.apply appsvc
salt 'minion-id' state.apply appsvc test=True
```

See `pillar.example` for the full pillar shape, available placeholders, and
worked examples (a minimal instance, two independent instances of the same
preset side by side, a direct-URL fetch, Grafana from its standalone tarball,
and a no-preset custom instance).

## How an instance is resolved

For every entry under `appsvc:instances`:

1. **Merge**: `defaults.yaml` -> `presets/<preset>.yaml` (deep-merged with any
   `appsvc:presets:<preset>` pillar override) -> the instance's own pillar.
   Later layers win; dicts merge recursively, everything else (including
   lists) is replaced wholesale - **except `svc.args`**, which is re-merged
   by flag name (`merge_args` in `lib/core.py`) right after. Mapping entries render
   as `{args_prefix}key=value`; string entries inside an args list render
   literally, so value-less flags like `--livereload` can be mixed in. A
   top-level raw string `svc.args` is still a complete args line and replaces
   the previous layer wholesale.
2. **Resolve version/source**: `svc.version_resolver` selects resolver logic
   for the app. The default `github` resolver turns `version: latest` into a
   concrete GitHub release tag using `/releases/latest` (NOT `/tags` - the
   tags endpoint isn't sorted by date/semver and can return tags that were
   never published as releases). `github_versionsort` instead lists GitHub
   releases and picks the highest semver-like tag, for repos whose
   `/releases/latest` can point at an LTS branch. The `grafana` resolver uses
   Grafana's API to resolve both latest/concrete versions and the real package
   URL, because Grafana archive names contain build IDs that are not derivable
   from the version alone. This network step runs only for instances **selected**
   by `appsvc:filter` (all of them when no filter is given).
3. **Expand placeholders**, in two passes (`expand` in `lib/core.py`):
   - *Phase 1* against grain-derived identity (`osarch`, `kernel_lower`,
     `cpuarch`, `grain_id` = the minion id) plus the instance's own static keys
     (`name`, `type`, `version`, `tag`, `tag_vstrip`) and any operator-defined
     `appsvc:globals` (literal `{key}` values shared by all instances; a key
     clashing with a reserved one fails loud) - enough to resolve `install_dir`,
     `svc.source`, `svc.exec`, etc.
   - *Phase 2* adds `install_dir`, `exec`, `args` (top-level raw string, or args
     list joined from `{args_prefix}key=value` mappings and literal string
     tokens; default prefix `-`), `user_name`,
     `user_group`, `home` (`user.home`, else `/root` for root, else
     `/home/<user.name>`), `svc_target`, `venv_dir`, and the runtime paths `nvm_dir`, `pyenv_root`, `tools_dir`, `env_sh` (per-user under `{home}` for a non-root `user.name`, global under `/usr/local` + `/etc/profile.d` for root; an explicit `nvm.dir` / `pyenv.root` / `shell_env.path` wins) - keys only knowable once phase 1 has run - so e.g.
     `systemd.units.main.Service.ExecStart: "{exec} {args}"` just works, without resorting
     to fragile nested-placeholder syntax like `{svc[exec]}`.
4. **Dispatch** the building blocks that apply, in a fixed order:
   `user_ssh` -> `install_dir` -> `dirs` -> `pyenv` -> `nvm` -> `tools` -> `env_sh` ->
   `sources` -> `config_file` -> `fetch` -> `venv` -> `php_fpm` -> `commands(pre)` -> `systemd_unit` ->
   `commands(post)` -> `cron` -> `nginx_vhost` (which receives `php_fpm`'s
   `{pool_key: socket}` map) -> `logrotate`.
   `install_dir` runs ahead of `config_file` on purpose: a config entry with
   `makedirs: True` would otherwise create the install dir root-owned before
   the service user's ownership is applied. `dirs` runs before `sources` so a
   checkout's parent exists; `sources` runs before `config_file` so a config
   entry can write into a checkout (e.g. a `.env.local`); such an entry (its `name`
   inside a source `target`) also `require`s that source, so a failed clone skips it
   instead of leaving a makedirs-created target behind, and a `dirs` entry inside a
   source target fails loud at render. `venv` runs after `fetch`: its
   `venv.requirements_files` may point at a `requirements.txt` that arrives
   inside the fetched archive.
   An optional `appsvc:filter` (usually typed on the CLI, e.g.
   `pillar='{appsvc: {filter: "name: vm* *gra*; preset: exporter*"}}'`) scopes
   the apply to a subset: semicolon-separated `name`/`preset` glob clauses, union
   semantics. Steps 1 and 3 (merge + expand) still run for **every** instance so
   a selected vmagent can gather any producer's scrape jobs; the filter gates
   only the **resolution** (step 2) and **dispatch** (step 4). Manual scoping,
   not change detection: a new exporter's job reaches vmagent only when vmagent
   is also in scope.
   A `block:` clause limits which **blocks** run for the selected instances, e.g.
   `filter: "name: mt-argon; block: cron"` or, for every instance,
   `filter: "block: cron nginx"`. Values are exact block names: `user` (user + ssh), `install_dir`, `dirs`, `pyenv`, `nvm`, `tools`, `shell_env`, `sources`, `config`, `svc` (the fetch), `venv`, `php_fpm`, `commands`, `systemd`, `cron`, `nginx`, `logrotate`
   (anything else fails loud). A skipped block contributes no requisites, so the
   rest still renders: `changed` holds only what this run applies (`block:
   systemd` restarts a unit only if its file changed), nginx gets the php-fpm
   sockets computed from pillar, a config entry inside a skipped source drops its
   `require` (the checkout is assumed to exist), and a command whose `onchanges`
   only watches skipped sources is not run at all - it has nothing to react to.
   `tests/test_dispatch.py` renders every single-block selection against fake
   states and checks that no requisite points at a missing state.
   `sources`, `fetch`, `config_file`, and `venv` each return the list of pyobjects
   requisite references that mean "the binary/config/requirement set
   changed"; `dispatch` threads that list into `systemd_unit`'s `watch`, so
   the service restarts exactly when it needs to - without any block
   hardcoding another block's state IDs.

Resolution runs in two passes over `appsvc:instances`: **pass 1** merges and
expands (steps 1-3) *every* instance into a fully formatted map; **pass 2**
gathers cross-instance scrape jobs and dispatches (step 4) the selected subset.
The split exists so a consumer can gather producers that were already formatted —
including producers excluded from this apply.

Before dispatch, an instance with `scrape_collect` gathers scrape jobs from all
instances with a matching `scrape.vmagent` selector and appends them to the
configured colon path, for example `config:promscrape.yml:contents:scrape_configs`.
This is host-local by design: producers declare
`scrape: {vmagent: <glob-or-list>, config: [...]}`, consumers opt in with
`scrape_collect`, and duplicate `job_name` values fail the render.

`scrape.config` is expanded by the **same two-phase pass as every other config**,
in the **producer's** scope (a job is declared by the producer but rendered into
the consumer's config, so it resolves against the producer) — `{name}`,
`{grain_id}`, `{install_dir}`, etc. all work. One caveat from the filter: since
the `latest` resolution is gated to selected instances, `{version}`/`{tag}` of a
producer *not* in the selected subset stay unresolved until a full apply. For
values outside the placeholder set, use Salt's own jinja in the **pillar**
(`instance: {{ grains["fqdn"] }}`), which renders before appsvc sees it — pillar
only, not a bundled `presets/*.yaml` (loaded with `yaml.safe_load`, no jinja).

## Directory isolation

Several sites on one host, each with its own user: a compromised site runs as
its user and can read every other site's world-readable files (a fresh file is
`644`). Lock each site's **top** directory - the home, when everything of the
site lives under it - with `750 <user>:www-data`:

```yaml
user:
  manage: true
  name: helium
  home: {name: /var/www/helium, group: www-data, mode: "750"}
install_dir: /var/www/helium/app     # under the locked home: nothing more needed
```

The user owns it (ssh, sftp and `StrictModes` work: the group gets no write);
nginx (www-data) traverses it via the group; every other user is stopped at
the door, whatever the modes inside. An `install_dir` outside such a home
(the default `/opt/services/{type}/{name}` has a shared `755` parent) needs its
own lock: `install_dir: {name: ..., group: www-data, mode: "750"}`. When
`install_dir` is the home itself, it takes the home's permissions.

The layers (defaults -> preset -> instance) merge these key by key, a plain
path counting as `{name: <path>}`. So a php-fpm preset can carry the policy and
the instance just the path:

```yaml
# preset                                         # instance
user: {home: {group: www-data, mode: "750"}}     user: {home: "/var/www/{name}"}
```

`mode: null` (or `group: null`) in a later layer drops it back to unmanaged.

What still breaks it, so check:

- **A site user in `www-data`** (`user.group` or `user.groups`): it can read
  every directory locked that way. The render fails for managed users; users
  added to the group outside appsvc are not seen.
- **Anything running as www-data** reads every site: the distro's default
  php-fpm `www` pool, or a pool whose `user` is www-data.
- **nginx's path**: every directory down to a vhost's `root` must let www-data
  through (group www-data, or `o+x`). A `750 <user>:<user>` directory on that
  path gives 403s.

No default changes: without a mapping, modes stay unmanaged as before.

## Building blocks (`blocks/*.sls`)

| block | settings key | does |
|---|---|---|
| `install_dir` | `install_dir` | create/own `install_dir` ahead of `config_file`/`fetch` - no-op with `install_dir: null`. Required: no default since 0.2 (bundled presets set it; the render fails if neither preset nor instance does); runs even without a `svc` block (e.g. a venv-only instance still needs somewhere to live). A path string, or `{name, user, group, mode}` (mode of the directory itself, never recursive; unset = unmanaged) - see [Directory isolation](#directory-isolation) |
| `fetch` | `svc` | fetch `svc.source` per its detected **kind**: `archive` (download, cache, optionally `tar`-extract and/or `move` it into `install_dir`, ensure it's executable) or `file` (a single script/bare binary compared as-is via `File.managed` - no cache hop, no extract). Kind is `svc.kind` if set, else inferred: `svc.tar` present or a recognized archive suffix (`.tar.gz`, `.tgz`, `.tar.bz2`, `.tbz2`, `.tar.xz`, `.txz`, `.tar.zst`, `.tar`) -> `archive`; an unsupported archive suffix (`.zip`, `.7z`, `.rar`, `.gz`, `.bz2`, `.xz`) raises rather than silently mis-fetching; otherwise -> `file`. Either kind: make any `svc.data_dirs` service-user-owned for writable state (program files stay root-owned). Archive re-extract is guarded by an optional `svc.version_check` `unless` command, or by `svc.version_stamp` (writes `.appsvc_version` into `install_dir` after a successful extract) as a generic fallback guard — **no default**, so with neither set the archive re-extracts (and the service restarts) every run. The `file` kind needs no guard at all: `File.managed` reports `changed` only when the fetched content actually differs |
| `venv` | `venv` | create/maintain a Python venv (`venv.dir`, default `{install_dir}/venv`) matching `venv.requirements`/`venv.requirements_files` - no-op unless `venv.manage`; runs after `fetch` so a requirements file shipped inside a fetched archive is already on disk. A single `Cmd.run` `unless`-guarded by a sha256 digest (interpreter version + `pip_args` + requirements file contents) computed on the minion at runtime, stamped inside `venv.dir` only on a successful install so a failed run retries. `venv.recreate_on_change` (default true) rebuilds with `--clear` whenever the requirement set changes; false only forces a fresh venv on a missing/wrong-version interpreter and otherwise reuses it. Root-owned like fetched program files; writable state still goes through `svc.data_dirs` |
| `user_ssh` | `user`, `ssh` | system user/group + `.ssh` (keys, authorized_keys, config, known_hosts) - no-op unless `user.manage`. `user.home` may be `{name, group, mode}` (name optional = default home): a `File.directory` on the home itself, after the user |
| `config_file` | `config` | render named config file(s) from `contents` using optional `format: yaml\|ini\|json` (default yaml), or `source`+`template` |
| `dirs` | `dirs` | create writable/working directories from a keyed map (string shorthand = path; `user`/`group` default to the instance user, `mode` default `"755"`, `makedirs` default true, `recurse: true` -> ownership only). Does not replace `svc.data_dirs` |
| `pyenv` | `pyenv` | pyenv from git at `rev` + each `versions` entry built (`pyenv install -s`) and the first set as `pyenv global`; build packages from `pyenv.build_pkgs` (defaults.yaml). Per-user under `{home}/.pyenv` for a non-root user, `/usr/local/pyenv` for root (`pyenv.root` overrides). `versions` is a list of **quoted** strings (`3.10` unquoted is the float 3.1). No-op without `versions`. Refs join `changed` |
| `nvm` | `nvm` | Packages from `nvm.build_pkgs` (defaults.yaml: git, curl; `[]` skips), then nvm from git at `rev` + each `versions` entry installed and the first set as the `default` alias. `{home}/.nvm` for a non-root user, `/usr/local/nvm` for root (`nvm.dir` overrides). `versions` is a list of quoted strings. No-op without `versions`. Refs join `changed` |
| `tools` | `tools` | single-file downloads (composer & co.) from a keyed map: `source`, optional `source_hash` (else no verification), `target` (default `{tools_dir}/<key>`), `mode` (quoted string, default `"755"`). Owned by the instance user. Refs join `changed` |
| `env_sh` | `shell_env` (optional overrides) | one generated file putting active nvm / pyenv / tools on PATH (`{env_sh}`: `{home}/.appsvc/<instance>.sh`, or `/etc/profile.d/appsvc-<instance>.sh` for root). For a non-root user a source line is **prepended** to `{home}/.bashrc` (`shell_env.profile` overrides, `false` disables) - prepended because Ubuntu's `.bashrc` returns early for non-interactive shells, which is how CI deploys over ssh run. Written only when nvm/pyenv/tools is active; not in `changed` |
| `sources` | `sources` | git checkouts from a keyed map: `git.latest` by default, `git.cloned` (clone if missing, never update) with `once: true`. `target` must be absolute after expansion (use `{home}`, not `~`). `force_reset` is **not** defaulted: a dirty tree fails loud instead of being discarded. Returns per-key refs; a change restarts the service (`changed` contract) and gates `commands.onchanges` |
| `commands` | `commands` | run ordered one-shot commands; `phase: pre\|post` controls before/after service start (default post), `when_set` gates on an optional input, `stdin` supports secrets, `onchanges: [sources:<key>]` (or `[sources]`) runs the command only when that source changed (see the trap in `presets/generic.yaml`) |
| `cron` | `cron` | crontab entries from a keyed map (`schedule` = five fields or one `@special`, `cmd`, `user` default the instance user, `comment`, `disabled`, `absent`), tagged with identifier `appsvc_<instance>_<key>`. Removing an entry from pillar does NOT remove it from the crontab - set `absent: true` |
| `php_fpm` | `php_fpm` | php-fpm **pools only** (never installs PHP) from the keyed map `php_fpm.pools`: one `/etc/php/<ver>/fpm/pool.d/<name>.conf` per pool (`version` is required and must be a quoted string; `name`, `user`/`group`, `listen`, `listen_*`, `log.error` (`php_admin_value[error_log]`), `log.slow` (php-fpm `slowlog`, with `log.slow_timeout` default 10 seconds - or a `"5s"`/`"1m"` string - and `log.slow_trace_depth` default 0; both need `log.slow`), raw `config` lines), plus one `php-fpm<ver> -t && systemctl reload php<ver>-fpm` per version, only on a pool-file change (`reload: false` opts out). Removing a pool from pillar does NOT delete its file. Returns `{pool_key: socket}` for `nginx_vhost`; does not restart the service. No-op without pools |
| `systemd_unit` | `systemd` | one `/etc/systemd/system/<name>.service` per key of the keyed map `systemd.units`, each merged over `systemd.defaults` (`{Unit,Service,Install}` + `name`, default `"appsvc_{name}_{unit}"`; bundled presets pin `name: "appsvc_{name}"` on their `main` unit). Every kept unit is enabled & (re)started and restarts on `watch` changes; `delete: true` stops, disables and removes a unit once, while a unit dropped from pillar is left alone. `{unit}` (key) and `{unit_name}` (resolved name) work inside a unit. Unit names must be unique across all instances, `.service` only, no `@`, no distro names (`nginx`, `php*-fpm`, ...). No units, or `systemd.manage: false`, renders nothing |
| `logrotate` | `logrotate` (optional tunables) | one `/etc/logrotate.d/appsvc-<instance>` composed from the logs the pillar already declares: every php pool `log.error`/`log.slow` (one stanza per PHP version, `postrotate` php-fpm's `reopenlogs` helper) and every vhost `log.access`/`log.error` (`postrotate nginx -s reopen`). Paths matching `logrotate.skip` (default `/var/log/nginx/*.log`, which the distro's nginx config already rotates) are left out, because logrotate aborts on a log listed by two configs; a path declared twice in one instance fails the render. Validated with `logrotate -d` before install; removed when no log remains. Defaults: daily, rotate 31, compress + delaycompress, `create 640 <user> <group>`. `logrotate.manage: false` disables |
| `nginx_vhost` | `nginx` | one vhost per key of `nginx.vhosts` (keyed map): built-in reverse proxy (`upstream`) or a custom jinja `template` (+ `vars`, and `php_fpm_sockets` in its context), optional per-vhost TLS and basic auth, logs under `log.access`/`log.error` (default `/var/log/nginx/<name>.{access,error}.log`; a template still sees them as `access_log`/`error_log`); ACME issuance per vhost, one `nginx -t && nginx -s reload` per instance - no-op unless `nginx.manage` |

`svc`/`systemd`/`nginx`/`php_fpm`/`config`/`commands`/`user`/`ssh`/`dirs`/`sources`/`cron`/`nvm`/`pyenv`/`tools`/`shell_env` are all
optional; an instance that doesn't set a block's key simply skips it. An instance
with no daemon (a pure app checkout) just has no `systemd.units`. A unit
without `Service.ExecStart` (and not `delete: true`) fails the render.

**Format changes** are listed in [CHANGELOG.md](CHANGELOG.md). Before anything
else, `compat.py` checks the raw pillar (every instance and pillar preset) for
shapes a later version changed, and fails the render listing all of them, each
with a one-line fix and its changelog anchor. There is no version field in
pillar.

`nginx.vhosts.<key>` entries declare `names` (required list), exactly one of
`upstream` / `template`, and at most one TLS source: `acme_account`,
`ssl_cert`+`ssl_key`, or neither. `name` defaults to `<instance>_<key>` and names
the sites-available file, upstream, ACME cert and logs. `acme_account` issues DNS
ACME certs (DNS accounts only - webroot accounts are not supported yet) through
the separately managed `acme` state/pillar; appsvc derives the
`/opt/acme/cert/<name>_<first-name>_*` paths and does not manage accounts.

**Migration (breaking):** the old single-vhost shape
`nginx: {manage, vhost_name: X, upstream: U, servers: [{names, acme_account}], auth_basic}`
now fails loud. Write it as
`nginx: {manage, vhosts: {X: {name: X, upstream: U, names: [...], acme_account: ..., auth_basic: [...]}}}`;
`name: X` keeps the same file and ACME cert path (the old default was the instance
name). One old `servers[]` entry becomes one vhost.

## The `lib/` layer

`lib/*.py` are plain Python modules with **zero Salt directives** — pure
functions over plain dicts, one module per area:

| module | holds |
|---|---|
| `lib/core.py` | placeholder expansion, deep merge, scrape collection, the apply filter, user home / known_hosts, home/install_dir permissions + the isolation check, keyed-map key checks, `svc.args` merge/join |
| `lib/release.py` | fetch kinds/targets, archive extraction, venv, `latest` resolvers + resolve cache (the only network code) |
| `lib/app.py` | commands (phases, onchanges), sources, dirs, cron, config rendering |
| `lib/runtimes.py` | runtime layout, nvm, pyenv, tools, env_sh |
| `lib/web.py` | php-fpm pools, nginx vhosts, logrotate |
| `lib/systemd.py` | `systemd.units` planning, unit-name checks, unit rendering |

Every module depends only on `core.py` (never the other way round, never on
each other). `compat.py` (old pillar shapes, see CHANGELOG.md) imports nothing
from `lib/`.

Unit-tested with plain pytest, one `tests/test_<module>.py` per module (run via
`python -m pytest tests/`), no minion required.

`init.sls` and the blocks load them with one-line
`from salt://appsvc/lib/<module>.py import ...` statements — the same
`from salt://...import` mechanism used for block files, no hardcoded path or
`sys.path` manipulation needed. The modules import `core.py` the same way, which
plain Python cannot parse, so `tests/conftest.py` serves them to pytest as the
package `appsvc_lib` (`from appsvc_lib.web import ...`), rewriting just those
import lines. Because pyobjects gives each
block file a frozen snapshot of `_globals` at exec time (before `init.sls`'s
own body runs), lib functions are NOT automatically in block `__globals__`.
Blocks that need helpers therefore import them in their own source with a
top-level `from salt://appsvc/lib/<module>.py import ...` line, so pyobjects populates
that block's globals during the block import itself.

## Presets (`presets/*.yaml`)

Bundled, ready-to-use type configs (`vlserver`, `vlagent`, `vmserver`,
`vmagent`, `vmauth`, `exporter_node`, `exporter_mysqld`, `exporter_redis`,
`grafana`, `redis_check`) loaded lazily and cached per Salt run, deep-merged with optional
`appsvc:presets:<name>` pillar overrides - so instances only need to specify
what differs from the bundled defaults (typically just `install_dir`, `user`,
`svc.version`, and `nginx`).

`presets/generic.yaml` is a safe, mostly-commented reference preset documenting
the full current feature surface: fetch/version resolution, config rendering,
commands syntax, systemd, nginx, user/SSH, and placeholder behavior.
