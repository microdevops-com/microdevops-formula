# binsvc — design whitepaper

Short orientation for maintainers (human or model): *why* `binsvc` is shaped the
way it is, plus the non-obvious mechanics you'd otherwise re-derive from scratch.
Read this before touching `init.sls`, `lib.py`, or the building-block contract.

- `readme.md` — how to use it. `pillar.example` — the full pillar shape.
- `TODO.md` — *live* open concerns / follow-ups.
- **This file records *settled* decisions** — don't relitigate the ones in §10
  without reading the rationale there first.

## 1. Origin

binsvc supersedes three overlapping, partial answers to "run a downloaded
binary under systemd, maybe several per host" — all left in production
untouched (binsvc is a parallel new state, not a refactor-in-place):

- **`exporter/`** (jinja) — type-registry + per-instance loop; good reusable
  primitives, but logic and directive emission are interleaved in dict-mutating
  jinja macros — untestable off-minion.
- **`victoriametrics/`** — same idea hardcoded to one binary family; origin of
  the nginx-vhost block and the `__VM_NAME__` string-substitution hack.
- **`application/`** (pyobjects, stalled) — the right *shape* (named
  building-block stages + a dispatch loop) but its fetcher was a one-off.

binsvc = `exporter`'s reusable-primitives idea + `application`'s dispatch shape,
with the logic/directives tangle solved by physically separating the two (§3)
and multi-instance support as a first-class requirement. It's also a trial run
for a future `application/` rewrite (§10).

## 2. What it does, in one paragraph

binsvc reads a dict of **instances** from pillar (`binsvc:instances`). Each
instance names an optional **preset** (a bundled type config — "this is a
vlserver") plus per-instance overrides. For each instance, binsvc
deep-merges `defaults.yaml` → preset → instance into one **settings** dict,
expands every `{placeholder}` string against the instance's resolved identity
(name, type, version, install dir, arch, …), then runs whichever **building
blocks** apply — fetch the binary, manage a user/SSH identity, render
config files, install & wire up a systemd unit (restarting it exactly when the
binary/config changed), optionally front it with an nginx vhost. Re-runs
are idempotent.

## 3. Core decision: split logic from directives

pyobjects' `from salt://path.sls import name` *looks* like a Python import but
isn't: `salt/utils/pyobjects.py` matches it with a regex over the **raw source
text** at template-processing time, *before* the importing file's body runs. The
target is fetched and `exec`'d with **a frozen copy of the importing file's
globals at that moment** and `Registry.enabled = False` — so only `def`/`class`
*statements* register; any top-level Salt-directive *call* would silently no-op.
Calls only take effect later when the importing file's body re-executes the
imported names with `Registry.enabled = True`.

**The unblock**: that restriction only bites files that *emit directives at
import time*. A file of pure `def`s with zero references to
`File`/`Cmd`/`Group`/`pillar`/`grains`/`__salt__` has no Salt coupling — it's
just a Python module, importable and pytest-able normally. So binsvc draws a
hard line:

- **`lib.py`** — one plain Python file. Pure functions over plain dicts/strings:
  placeholder expansion, deep-merge, release resolution, archive/tar/unit
  construction, arg joining/merging. Zero Salt directives. Fully covered by
  `tests/test_lib.py` (plain pytest, no minion).
- **`blocks/*.sls`** — `#!pyobjects` fragments of `def`s that emit directives
  when called; imported into `init.sls` via `from salt://binsvc/blocks/x.sls
  import y`.
- **`init.sls`** — orchestrator. Owns all I/O (`pillar`, `grains`,
  `get_salt_file`), imports the blocks, drives the per-instance loop.

### How lib helpers reach blocks (no sys.path, no hardcoded paths)

`init.sls` imports the helpers *it* calls directly. **Each block carries its own
top-level `from salt://binsvc/lib.py import <names>` line** for the helpers it
needs. This matters because of the frozen-globals snapshot above: names added to
`init.sls`'s globals *after* a block was imported are not visible inside that
block. Putting the import in the block's own source makes pyobjects populate that
block's globals while importing the block itself. Keep these imports on **one
line** — the preprocessor is line-based and breaks on multi-line parenthesized
imports.

*Rejected alternatives (don't reintroduce):* `cp.cache_dir`+`sys.path.insert`
(returned empty under salt-ssh → `IndexError`); a hardcoded `FORMULA_DIR` on
`sys.path` (brittle to deploy path); a process-global `sys.modules["lib"]`
injection (generic name → cross-formula collision risk). See `TODO.md` item 1.

`DEFAULTS` and presets load via `get_salt_file("salt://binsvc/...")` — a helper
in `binsvc/utils.sls` using `salt.fileclient` directly. This works under
salt-ssh; `__salt__["cp.get_file_str"]` does **not** (different fileclient
plumbing in the salt-ssh render context).

## 4. Resolution pipeline

```
binsvc:
  presets:                 # optional pillar overrides, deep-merged over presets/<name>.yaml
    <preset_name>: {...}
  instances:
    <instance_name>:
      preset: <preset_name>   # optional — omit to drive everything from pillar
      install_dir / user / ssh / svc / config / systemd / nginx: {...}
```

`init.sls` first merges all instances, then resolves and dispatches each one:

1. **Load preset** (`load_preset`) — parse `presets/<name>.yaml` once per run
   (`_preset_cache`), deep-merged with any `binsvc:presets:<name>` pillar
   override.
2. **Merge** — `settings = merge(defaults, preset, instance)`. Dicts merge
   recursively; everything else (incl. **lists**) is replaced wholesale by the
   more-specific layer. (`svc.args` is the one exception — §10.)
   This pass runs for every instance before any instance is expanded or
   dispatched, so a consumer can gather merged producer stanzas from the same
   host without depending on declaration order.
3. **Resolve version/source** (`resolve_latest_version` → `lib.py`'s
   `resolve_latest`, which does the HTTP via `requests.get`, cached on the render
   host — §10) — through the named `svc.version_resolver` (`github` by default).
   GitHub resolvers only resolve `version: latest`, freezing `svc.version`/
   `svc.tag` to the concrete release tag and requiring `svc.source` as the URL
   template. Grafana resolves both `latest` and concrete versions through its
   packages API, filling `svc.source` and `svc.source_hash` because the tarball
   URL contains a build ID that is not derivable from the version alone (§10).
4. **Expand placeholders, two passes** (`expand`, §5).
5. **Inject gathered scrape jobs** when `scrape_collect` is set. `vmagent` uses
   this to append literal jobs from matching producers' `scrape` stanzas into
   `config.promscrape.yml.contents.scrape_configs`, reusing the normal
   `config_file` block.
6. **Dispatch** building blocks in fixed order, threading "what changed" into
   systemd's restart trigger (§6).

## 5. Placeholder expansion: two phases, no third

`lib.py` provides `deep_format(value, scope)` (recursively `format_map`s every
string in a nested structure; missing keys left as literal `{key}` so partial
scopes don't blow up) and `expand(mapping, scope, rounds=3)` (folds the
mapping's own progressively-expanded values into scope each round, so keys can
reference each other regardless of order). This one tested function replaces
`application/`'s `format_dict_*` and `victoriametrics/`'s `__VM_NAME__` hack.

Some values aren't knowable from the merged settings at all — `install_dir` is a
template (`/opt/services/{type}/{name}`) only concrete *after* expansion, yet
`svc.exec`/`ExecStart`/nginx paths want the *resolved* value. Rather than
nested-placeholder syntax (`{svc[exec]}`), `init.sls` runs `expand` **twice**:

- **Phase 1** scope: grain identity (`osarch` via `normalize_osarch`,
  `kernel_lower`, `cpuarch`, `grain_id` = `grains:id`) + static keys (`name`,
  `type`, `version`, `tag`, `tag_vstrip`) + operator-defined `binsvc:globals`
  (overlaid via `merge_globals`, which raises if a global shadows a reserved
  key — see §10). Resolves `install_dir`, `svc.source`, `svc.exec`, …
- **Phase 2** scope: phase 1 **plus** `install_dir`, `exec`, `args`
  (raw string args, or structured `svc.args` joined through `join_args` using
  `svc.args_prefix`, default `-`), `user_name`, `user_group`. So
  `ExecStart: "{exec} {args}"` just works.

A **third**, narrower expansion lives *inside* `fetch_archive.sls`:
`tar`/`move` may reference `{file}` (the archive's local cache path, computed in
the block by `archive_path`) — genuinely unknowable earlier. **If tempted to add
a phase 4 or a new cross-referencing placeholder: first ask whether the value
can be computed inside the block that needs it (like `{file}`).** Narrow late
expansions compose better than ever-earlier global phases.

## 6. Dispatch & the `changed`/`watch` contract

`dispatch(prefix, settings)` runs, per instance, in fixed order:

```
user_and_ssh → config_files → fetch_archive → commands(pre)
  → systemd_unit(watch=changed) → commands(post) → nginx_vhost
```

Order matters: `fetch_archive` needs the install-dir owner (from `user_and_ssh`)
before it creates the dir; `systemd_unit` must know everything that triggers a
restart before wiring `onchanges`; `commands(pre)` runs after binary/config are
in place and before service start; `commands(post)` runs after the service is
known running when systemd is managed.

**The contract**: `config_files` and `fetch_archive` return a *list of
pyobjects requisite references* (`[File(id)]`, `[Cmd(id)]`,
...) meaning "if these change, the service should restart".
`dispatch` concatenates them and passes them as `systemd_unit`'s `watch=`, folded
into its `onchanges` alongside the unit file. **No block hardcodes another
block's state IDs** — adding a config mechanism never requires touching
`systemd_unit`; it only honors the contract (return the list, or
`None`/`[]` if nothing changed).

The same decoupling pattern handles post-systemd ordering: `systemd_unit`
returns its "service is running" requisite and `dispatch` passes that as
`commands(post)`'s `require`. If systemd management is disabled, post commands
still render, just without a service-running requisite. Commands deliberately
do **not** feed the `changed` list; setup commands are not "new binary/config"
events and should carry their own `unless`/`onlyif` if they need idempotency.

binsvc is archive-only today. Package fetch support was deliberately removed
when no planned users remained; if package support returns, it should come back
as a real fetch registry with the same `changed` contract rather than by
reusing `version_resolver` for fetch semantics.

## 7. Multi-instance

A first-class requirement (the ecosystem usually assumes one instance per host).
Every block receives a `prefix` (e.g. `["binsvc", "vl_main"]`) and derives
**all** state IDs, paths, and unit names from it (`sid = "_".join(prefix)`, …).
`settings["name"]` is always the **instance key**, so `{name}` placeholders
disambiguate even when `{type}` is shared. Two instances of one preset never
collide — as long as `{name}` appears in the relevant template (every bundled
default/preset ensures it). `pillar.example`'s `vl_main`/`vl_secondary` proves
it: two independent vlserver instances side by side, distinct ports/users/units.

## 8. Presets

A preset (`presets/<name>.yaml`) is a bundled, ready-to-use type config, loaded
lazily and cached per run (`load_preset`/`_preset_cache`). Presets are **not**
meant to be copied into pillar — `binsvc:presets:<name>` exists only for
*targeted overrides* (pin a version, change a port), deep-merged over the bundled
file. An instance needing something a preset lacks just sets the key directly
(see `custom_exporter` in `pillar.example` — no preset at all).

The shipped presets are **design drivers** for archive-only service management
with more than one version/source resolver: VictoriaMetrics-family presets use
GitHub release tags and source templates; `grafana` uses Grafana's version and
packages APIs because the tarball URL is API data, not a stable format string.
Standalone `victoriametrics/`/`grafana/` formulas already exist and remain the
production path — these presets are not replacements or a migration invitation.

## 9. Testing

- **`lib.py`**: `~/venv/bin/python -m pytest tests/ -v` — dict/string fixtures,
  no minion, no mocked Salt internals (lib never touches them). This is the
  payoff of the split: the fiddliest logic is the easiest to test.
- **Render path** (the pyobjects wiring) is **not** covered by the unit tests —
  they import `lib.py` directly, bypassing pyobjects entirely. It must be checked
  with a real render (`salt-call --local state.show_sls binsvc`, and a salt-ssh
  render — the two use different fileclient plumbing; this area has bitten
  salt-ssh before). The TODO item 1 change was validated this way.

## 10. Settled decisions — do not relitigate

(For *open* items and follow-ups, see `TODO.md`. These are closed.)

- **GitHub release resolvers read releases, not tags.** GitHub's `/tags` is
  unsorted (repo-internal order, not date/semver) and can include tags never
  published as downloadable releases. The default `github` resolver uses
  `/releases/latest`, which matches GitHub's own latest-release pointer. Repos
  with LTS branches can use `github_versionsort`: it lists releases, filters out
  prereleases/drafts, strips known suffixes like `-cluster`, and picks the
  highest semver-like tag. VictoriaMetrics-family presets use this because
  GitHub's latest pointer can target an LTS branch while a higher current
  release exists.
- **Wholesale list-merge, with one exception.** `merge` replaces lists wholesale
  (append/index/key-merge strategies are ambiguous and formula-specific;
  "more-specific layer wins" is predictable). The exception is **`svc.args`**:
  `merge_args` (tested) merges by flag name so an instance can override just
  `httpListenAddr` without restating the preset's other flags; `init.sls`
  re-merges `svc.args` right after the generic merge. Mapping entries render as
  `{args_prefix}key=value`, with `args_prefix` defaulting to `-`; string entries
  inside an args list are passed through as literal tokens for value-less flags.
  A top-level raw string `svc.args` is also passed through unchanged, but
  replaces the previous layer wholesale. Deliberately **not**
  generalized into `merge` — structured args' "ordered list of single-key
  mappings" shape is what makes by-name merging well-defined, and that shape
  isn't universal (cf. `nginx.auth_basic`/`servers`). `merge_args` also
  falls back to wholesale replace when a layer is a top-level string or repeats
  a flag (e.g. multiple `remoteWrite.url`) rather than guess.
- **ACME in `nginx_vhost` is a cross-formula dependency.** binsvc accepts
  per-server `acme_account` values, but never manages accounts; the separate
  `acme` state/pillar must create `/opt/acme/home/<acct>/verify_and_issue.sh`.
  The nginx block derives cert paths internally from vhost name and the first
  domain instead of asking pillar to cross-reference expand placeholders, mirrors
  the acme `verify_and_issue` command inline with `shell="/bin/bash"` and
  `success_retcodes=[2]`, and makes nginx reload require issuance so `nginx -t`
  sees cert files before validating the vhost. ACME renewal-triggered reloads
  remain owned by the acme formula.
- **Two-phase expand, no phase 3.** See §5 — prefer computing a value inside the
  block that needs it over adding a global phase.
- **`binsvc:filter` gates dispatch, never the merge.** An operator-typed
  selector string (`"name: vm* *gra*; preset: exporter*"`, semicolon clauses,
  union semantics, `fnmatch` globs) scopes a `state.apply` to a subset of
  instances. It is intentionally a small **string DSL**, not structured pillar,
  because it is typed by hand on the CLI where nested `{"":{"":[""]}}` is
  error-prone; `parse_filter` hardens it (`split(":", 1)`, fail loud on unknown
  key / empty globs). The pass-1 loop still merges **all** instances so
  `collect_scrape_jobs` sees the full set — only the pass-2 `dispatch` call is
  filtered (unselected instances also skip the resolve/expand network cost).
  This is **manual scoping, not change detection**: filtering to a new exporter
  won't refresh vmagent's scrape config until vmagent is also in scope.
- **`binsvc:globals` are scope, not settings.** Operator-defined placeholders
  (`{foo}`) shared by every instance live in the **expand scope**, never in the
  `defaults→preset→instance` merge — they are template variables, not per-instance
  config. Values are **literal** (inserted verbatim, no recursive expansion).
  A global that collides with a reserved/derived placeholder (`name`, `type`,
  `grain_id`, …) **fails the render** via `merge_globals` rather than silently
  shadowing it (a collision is almost always a typo). Reserved names always win
  by being un-overridable, not by precedence. `{grain_id}` is the minion id
  (`grains:id`) — named for the machinery, not "hostname", since the two can
  diverge.
- **Scope: prebuilt-binary service management, not app deployment.**
  PHP-FPM/LEMP is out of scope (owned by `app/`). Unifying "download a binary"
  with "deploy a PHP app with fpm pools" would yield a worse abstraction.
- **`config_file` is intentionally narrow** — one or two managed files per
  instance. `contents` renders through `render_config` as yaml/ini/json, or an
  entry can use `source`+`template`. It is still not a replacement for
  `_include/file_manager`; provisioning directories remain a separate
  `config_dir` gap (TODO #9).
- **`commands` is a generic mechanism, not app logic.** Entries run in
  declaration order and default to `phase: post` (after service start), because
  API calls and CLIs often need a live service. Use `phase: pre` only for setup
  that must happen before first start and does not need the service's migrated
  runtime state. `when_set` gates optional semantic inputs before placeholder
  expansion can leave a literal like `{admin_password}`; `stdin` is preferred
  for secrets. Commands do not trigger systemd restarts through the
  `changed`/`watch` contract; use explicit `unless`/`onlyif` for idempotency.
- **Future `application/` rewrite.** The reusable nucleus is `expand`/`merge` +
  the `dispatch`/`changed` contract + the merge pipeline — *not* the
  fetch/release/systemd helpers, which are binary-service-specific and would need
  siblings for PHP-FPM/Docker/static-site types.
- **`store` removed; `version_resolver` added.** `store` conflated fetch
  strategy with "how does latest resolve?" Once apt/package support was dropped,
  fetch became archive-only and the only real variation left was resolver logic.
  GitHub's releases URL moved from `defaults.yaml` into `lib.py`; it is stable
  code, not useful pillar data.
- **Grafana resolves package source through the API, even for pinned versions.**
  Grafana's versions API exposes stable versions (`13.0.2`), but the package
  URL contains an extra build ID segment (`..._26816849631_...`) that is only
  present in `/versions/<version>/packages`. Therefore `version_resolver:
  grafana` is a package resolver: for `latest`, first pick the newest stable
  version; for both `latest` and concrete versions, select the Linux package
  matching normalized `osarch`, then fill `source` and `source_hash`. Requiring
  users to guess or copy the full URL for pinned versions would make the preset
  less correct than the API.
- **Cross-instance scrape sharing is the first intentional non-local read.**
  `vmagent`'s rendered promscrape config may include jobs declared on exporter
  instances, so it cannot always be understood from the vmagent pillar alone.
  This Puppet-exported-resources-style non-locality is contained deliberately:
  producers use an explicit `scrape.vmagent` selector, jobs are literal
  operator-authored data, collection is host-local, and duplicate `job_name`
  values fail the render instead of being renamed silently.
- **Program files root-owned; writable state via `svc.data_dirs`.** `fetch_archive`
  extracts as root (`--no-same-owner`), so program files are root-owned — a
  compromised service can't rewrite its own binary. Dirs the service must write
  into are declared in `svc.data_dirs` and made service-user-owned (recursively,
  to fix ownership of contents the archive shipped) after extraction. Don't
  "simplify" by extracting as the service user or `chown -R`-ing the whole tree —
  that collapses the split. VL/VM need no `data_dirs` (their writable
  `storageDataPath` doesn't exist post-extract, so the service creates it under
  the user-owned install_dir); Grafana does, because its tarball ships the data
  dir root-owned.
- **Re-extract idempotency (`svc.version_check`) is opt-in, no default.** The
  extract `Cmd`'s `unless` guard comes from an explicit `svc.version_check` raw
  command (templated; `{binary}` = exec's first token and `{file}` filled in the
  block, the rest by `expand`). There is deliberately **no built-in default**:
  the old hardcoded `[[ $(<binary> -version 2>&1) =~ <ver> ]]` silently assumed a
  `-version` flag, which won't hold for every future service. The cost of no
  default is real and intended — a preset/instance with **no** `version_check`
  re-extracts every run, so the extract reports "changed" and the service
  restarts every apply. Every bundled preset declares one explicitly; binaries
  with no version flag can point it at a stamp file or any command (exit 0 = up
  to date), or omit it to accept restart-on-every-apply.
- **Version resolution is cached on disk at render time, with a NAT caveat.**
  Resolution runs during rendering, so a many-minion highstate (or repeated
  salt-ssh runs) would otherwise hit a fresh API request each time and blow the
  unauthenticated GitHub limit (60 req/hr/IP). `cached_get_json` (`lib.py`) keeps
  a TTL'd file cache under `{cache_dir}/resolve/` (`resolve_cache_ttl`, default
  1h, `0` disables), shared across render *processes* on the host: a lock-free
  read on a fresh entry; an `flock`-guarded, double-checked single refresh on a
  cold/expired one; atomic temp+rename writes; and **serve-stale-on-error** so a
  GitHub blip or rate-limit serves the last-known value instead of failing the
  render. It also makes a whole highstate resolve `latest` to one consistent
  version. **Known, accepted unhappy path:** minions that render *locally* behind
  a shared NAT egress IP share the rate-limit budget but **not** this filesystem,
  so the cache can't help them — use a GitHub token (TODO #2) there. (Whether
  rendering is host-shared depends on your setup; the cache is best-effort and a
  harmless no-op for any render that doesn't share the cache dir.) An optional
  top-level `binsvc:github_token` pillar lifts GitHub to 5000 req/hr (sent as a
  Bearer header by the github resolver only, never to grafana.com, and kept out
  of the cache key) — this is the mitigation for the NAT path.

## 11. Where to look for what

| Question | Look at |
|---|---|
| What pillar keys does an instance support? | `pillar.example` (inline docs), `readme.md` placeholder table |
| What does the merged/expanded settings dict look like for instance X? | `state.show_sls binsvc` on a minion |
| Why can `lib.py` functions be called inside block functions? | §3 — each block has its own top-level `from salt://binsvc/lib.py import ...` |
| How do I add a version resolver? | Add a pure helper in `lib.py`, register it in `VERSION_RESOLVERS`, and have it return a settings patch for `resolve_latest` |
| How do I add a building block (cron, logrotate)? | New `blocks/<name>.sls` exporting `<name>(prefix, settings)`; wire into `dispatch`, guarded by its settings key / `manage: true` |
| How do I add app-specific management (Grafana datasources, etc.)? | `docs/extending-with-app-blocks.md` — generic gap → generic block; app knowledge → preset data; irreducible app logic → a thin app block |
| Why is `{install_dir}` sometimes a real path, sometimes a template? | §5 — depends which expansion phase |
| Is it safe to run twice / does it restart unnecessarily? | §6 — restarts are `onchanges`-based off the `changed`/`watch` contract |
| What's still open / planned? | `TODO.md` |
