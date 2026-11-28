# appsvc — TODO / open concerns

Stable tracker for known issues and follow-ups. Survives context compaction
and new sessions. Update the status box when something is done; don't delete
items — strike them or mark `[x]` with a one-line resolution note so the
history of *why* a decision was made stays visible.

Status legend: `[ ]` open · `[~]` in progress · `[x]` done · `[-]` won't do (with reason)

Source: code review on 2026-06-09 (Opus) of the appsvc state. Each item lists
**why** it matters and **what** to do, with file references.

---

## P1 — architecture / correctness

### [x] 1. Replaced the `sys.modules["lib"]` injection with per-block imports
**Resolved 2026-06-09 (spike by Sonnet, passed real render validation).**

The global `sys.modules["lib"]` injection (and its generic-name collision risk
+ in-body deferred-import boilerplate) is gone. The hypothesis held: pyobjects
runs its `from salt://...import` regex pass on **each** file as it's imported,
so a block carrying its *own* top-line `from salt://appsvc/lib.py import <names>`
gets those names in its globals before its body runs — no frozen-globals bug,
no global module. `init.sls` dropped the injection + `import sys`/`import types`;
`blocks/fetch_archive.sls` and `blocks/systemd_unit.sls` now import their
helpers at module top. Validated via real `salt-call` / `salt-ssh` render (unit
tests don't exercise the pyobjects path). Docs updated: `lib.py` docstring,
`readme.md`, `WHITEPAPER.md` §3.

### [x] 2. `resolve_latest` render-time network I/O — hardened
**Resolved 2026-06-18.**

- Timeout: `_get_json` calls `requests.get(..., timeout=10)`.
- On-disk TTL cache (`cached_get_json`, `resolve_cache_ttl` default 1h): collapses
  a many-minion highstate / repeated salt-ssh runs into one API call per URL per
  window, shared across render processes via `flock` + atomic writes, with
  serve-stale-on-error so a GitHub blip/rate-limit doesn't fail the render.
  Covers GitHub and Grafana.
- Optional `appsvc:github_token` (top-level pillar) → Bearer auth on the github
  resolver only (never sent to grafana.com, kept out of the cache key); lifts
  GitHub to 5000 req/hr. This is the mitigation for the **NAT unhappy path**
  (minions rendering locally behind a shared egress IP don't share the cache
  filesystem).

Tests in `tests/test_lib.py`; documented in WHITEPAPER §10, `defaults.yaml`,
`pillar.example`. Render/concurrency path itself is render-only (not unit-tested).

### [x] 3. Binaries are fetched unverified by default
**Resolved 2026-06-20.** All five victoria* presets now ship a derivable
`source_hash` pointing at the published `_checksums.txt` alongside each release
archive (`vlserver.yaml`, `vlagent.yaml`, `vmserver.yaml`, `vmagent.yaml`,
`vmauth.yaml`), so
integrity verification is the default rather than opt-in. `fetch_archive` still
falls back to `skip_verify=True` only when a preset/instance declares no
`source_hash` (kept for resolvers/sources that publish no checksum file).

### [x] 11. Remove `store`; introduce `version_resolver` (archive-only)
**Resolved 2026-06-18.**

Outcome note: appsvc is archive-only; `store`/`FETCH_HANDLERS`/`fetch_package`
are removed, `version_resolver` drives GitHub vs Grafana resolution, and
Grafana resolves package URLs/checksums through the packages API because its
tarball URL is not derivable from the version alone.

**Decision:** drop apt/package support entirely (no planned users), so the fetch
axis collapses to a single archive strategy and the `store` key loses its reason
to exist. `store` conflated two axes — *how to fetch* (archive vs apt) and *how
to resolve `latest`* (which API + response shape). Removing apt eliminates the
first; the second becomes an explicit `svc.version_resolver` key
(`github` | `grafana`), with `svc.source` always a full tarball URL.

**Driver:** installing Grafana via tarball (off-GitHub, own version API) is not a
new *store* — it's a second *resolver*. `store: github` vs `direct` was already
*only* a resolution distinction (both fetch via `fetch_archive`), confirming the
conflation.

**Verified Grafana version API (2026-06-18):**
- `https://grafana.com/api/grafana/versions/latest` → **404, does not exist.**
- `https://grafana.com/api/grafana/versions` → `{"items": [...]}`, newest-first,
  **includes nightly/beta** — must filter `channels.stable == true`. First stable
  was `13.0.2`. Version strings have **no leading `v`**.

**Consequences:** delete `blocks/fetch_package.sls` + `FETCH_HANDLERS`; Grafana
flips to appsvc-managed systemd (tarball has no postinst, so `systemd.manage`
goes true + the preset gains a `systemd:` section); WHITEPAPER §4/§8/§10 + readme
need updating *as part of the change* (don't pre-edit — keep doc/code in sync).

### [x] 16. Split `fetch_archive` into `install_dir` + kind-aware `fetch`
**Resolved 2026-08-20.**

**Why:** appsvc assumed every install was "download a tarball and extract it."
That assumption breaks for the first Python daemon (`redis_check.py`, a single
plaintext script served from a URL or `salt://`) and for bare binaries with the
same shape - neither has anything to `tar`-extract. It also breaks for a
venv-only, PyPI-installed daemon with no `svc` block at all: nothing created
its `install_dir`, because that used to happen inside `fetch_archive`, gated on
`svc` being set.

**What changed:** `blocks/fetch_archive.sls` split into `blocks/install_dir.sls`
(the directory creation, now dispatched unconditionally - not gated on `svc`)
and `blocks/fetch.sls` (renamed `fetch_source`), which picks a fetch **kind**
via `lib.py`'s `fetch_kind` - `archive` (today's download/cache/tar-extract
path, byte-identical for every bundled preset - all declare `svc.tar`) or
`file` (a bare script/binary compared as-is via `File.managed`, no cache hop,
no extract). `File.managed` already hashes and compares content, which is a
strictly better idempotency primitive for this shape than a guarded extract
`Cmd.run` with a hand-written `unless` - no `version_check`/`version_stamp`
needed for `kind: file` at all. The archive path also gained `svc.version_stamp`
(a generic idempotency-stamp fallback for binaries with no `--version` flag -
the source-tarball equivalent of `exporter`'s `.salt_version_info`) and
`svc.executable` (override the default "exec's first token" chmod target,
needed once `exec` can start with a not-yet-existing venv interpreter path).

Verified backward-compatible: all 10 active bundled presets declare `svc.tar`,
so `fetch_kind` resolves them to `archive` via the same rule regardless of the
new kind machinery; the no-preset `custom_exporter` pillar example (no `tar`
key, `.tar.gz` source) resolves to `archive` via the suffix rule instead.
`svc_target` (a new phase-2 placeholder, `""` when there's no `svc.source`) is
what will let a venv-based `ExecStart` reference the fetched script without
repeating its path - for a not-yet-implemented `venv` block, tracked
separately once it lands.

### [x] 17. `venv` block — managed Python venv for Python daemons
**Resolved 2026-08-20.**

**Why:** the first Python daemon (`redis_check.py`, see item 16) needs a
Python interpreter with its own dependencies, not the system `python3` and
whatever happens to already be installed there. Generic mechanism (extending-
with-app-blocks.md litmus test #2), not app-specific: any PyPI-distributed
daemon wants this, including one with no `svc` block at all.

**What changed:** new top-level `venv:` key (not `svc.venv` - a
PyPI-distributed daemon with `venv.requirements` and no `svc` block is a valid
instance), `blocks/venv.sls` (`python_venv`), and `lib.py` command builders
(`venv_requirement_paths`, `venv_digest_command`, `venv_guard_command`,
`venv_build_command`). Dispatched after `fetch_source` (a `requirements.txt`
can arrive inside a fetched archive) and before `commands(pre)`, its `Cmd.run`
folded into the `changed`/`watch` contract. New phase-2 placeholder
`{venv_dir}` (never `{venv}` - `expand` folds top-level settings keys into
scope, so `{venv}` would render the config dict's repr).

Diverges from `exporter/macro.jinja`'s venv macro on purpose: idempotency is a
sha256 digest of interpreter version + `pip_args` + every requirements file's
*content*, computed on the **minion at runtime** (not render time, and not by
parsing `pip freeze -r ... =~ WARNING`, which only catches missing packages,
not version-constraint drift). The stamp lives *inside* `venv.dir` (a
`--clear` recreate invalidates it automatically) and is written *last*, only
on a successful `pip install`, so a failed install retries next run; the
*inline* requirements file lives in `install_dir`, *outside* the venv, so a
recreate can't eat it mid-run. `venv.recreate_on_change` (default true)
rebuilds with `--clear` on any requirement-set change; false only forces a
fresh venv on a missing/wrong-interpreter-version guard failure and otherwise
reuses the venv, letting `pip install` update packages in place.
`venv.python` (configurable, default `python3`) is always used explicitly -
stock Debian has no bare `python`. The `unless` guard is deliberately ONE
shell command chained with `&&`, not a list, sidestepping Salt's
all-vs-any `unless` list semantics. The venv is root-owned, like fetched
program files (§10's "a compromised service can't rewrite its own binary"
rule); writable state still goes through `svc.data_dirs`.

First real consumer: `presets/redis_check.yaml` (asyncio Redis/Valkey
PING-latency checker, `redis>=4.2`/`PyYAML>=5.0`) + a `redis_check` instance
in `pillar.example`, exercising `kind: file` fetch (item 16) + `venv` +
`{svc_target}`/`{venv_dir}` together end to end. Sits beside item 9
(`config_dir`), still open, in the P4 generic-block vocabulary gap list.

### [x] 12. Grafana preset validated against a real tarball
**Resolved 2026-06-18 — a real salt-ssh run installs and runs Grafana.**

`--homepath` was fixed to `{install_dir}` and `tar.unpack: "grafana-{tag}"`
matches the real tarball top-dir (strip-1 extract + service start succeed).
Residual, tracked under #14: whether `fetch_archive`'s `version_check`
unless-guard (`grafana -version`) makes a *second* run a no-op or re-extracts is
a separate idempotency question (`version_check` assumes `binary -version`).

---

## P2 — docs / honesty

### [x] 4. lib.py docstring corrected
**Resolved (via item 1's per-block-import approach).** The docstring now
describes blocks carrying their own top-level `from salt://appsvc/lib.py import`
lines (pyobjects populates each block's frozen globals at the block's own
import) — the old "lands in block `__globals__` automatically" claim is gone.
(The `sys.modules` injection #4 originally pointed at was itself superseded by
item 1, so the docstring reflects the final mechanism.)

### [x] 5. WHITEPAPER trimmed; "generic reusable lib" framing tempered
**Resolved 2026-06-18.** WHITEPAPER cut from ~459 to ~307 lines (decisions +
gotchas; tests document behavior — later growth is genuine new decisions, not
prose). §10 states plainly that the reusable nucleus for a future app-mgmt
rewrite is the *pipeline shape* (merge→expand→dispatch + the `changed`
contract), **not** the fetch/release/systemd helpers, which are
binary-service-specific. The domain-specificity of those helpers as a *code*
concern (`version_check` assuming `binary -version`) moved to #14 (it was a code
item bundled into this doc one).

---

## P3 — polish / smaller

### [x] 6. `config_file` is YAML-centric but named broadly
**Resolved 2026-06-18.**

Outcome note: `config[*].format` now supports yaml/ini/json through tested
`lib.render_config`; Grafana uses `format: ini` for `conf/custom.ini`.

### [-] 7. nginx basic-auth secrets in plaintext pillar, rewritten every run
**Closed 2026-06-20 — accepted known behavior, no change.**
**Where:** `blocks/nginx_vhost.sls` (`Webutil.user_exists(..., force=True)`),
`pillar.example` (`password: change-me`).

Passwords in pillar plaintext and the `force=True` htpasswd rewrite are
understood and accepted: secret-handling is an operator/pillar-encryption
concern repo-wide, not a appsvc-specific defect, and the per-run rewrite is
idempotent in effect. No behavioral change planned.

### [-] 8. Working-tree `.pyc` / pytest cache
**Closed 2026-06-20 — cosmetic, ignored by design.**
**Where:** `appsvc/__pycache__/lib.cpython-311.pyc`,
`appsvc/tests/__pycache__/`, `appsvc/.pytest_cache/`.

`.gitignore` already covers `__pycache__/` and `.pytest_cache/`, so they never
reach a commit. Their presence in the working tree is fine and expected after
running tests — nothing to do.

### [x] 14. `version_check` made data-driven (`svc.version_check`), no default
**Resolved 2026-06-18.** The hardcoded `binary -version` guard is gone; the
extract `unless` is now an explicit, templated `svc.version_check` command
(`{binary}`/`{file}` filled in `fetch_archive`, the rest by `expand`). **No
default** (user's call): without it the archive re-extracts and the service
restarts every apply — so all three bundled presets declare
`[[ $({binary} -version 2>&1) =~ {tag} ]]` explicitly. `lib.py`'s `version_check`
helper + its test were removed (dead). Documented WHITEPAPER §10, readme,
pillar.example. (Grafana `-version` confirmed working by the user; the run-twice
idempotency check is now just "does the preset's version_check match" — render-path.)

---

## P4 — generic-block vocabulary gaps

Source: app-blocks design discussion, 2026-06-18. These are *generic* missing
mechanisms (not app-specific work) surfaced while planning extended app
management — see `docs/extending-with-app-blocks.md`. Filling them lets
~80% of "extended Grafana/Loki/Prometheus management" be expressed as preset
data over generic blocks, with no app-specific code. `config_file` now covers
yaml/ini/json; TOML can be added later if a real consumer needs it.

### [ ] 9. `config_dir` block — render N files into a directory
**Where:** new `blocks/config_dir.sls`; dispatched like other blocks from
`init.sls`.

**Why:** `config_file` (#6) covers "one or two named files." Provisioning
directories (Grafana `provisioning/datasources/*.yaml` + `dashboards/`,
Prometheus `conf.d/`, etc.) need *N* files into a directory. No app-specific
knowledge — just "render this set of files here."

**What to do:** A block taking a dir + a set of named file entries (reusing the
`config_file` rendering path / `format:` hint from #6), returning the
`changed` contract (§6 of WHITEPAPER) so systemd/reload threads correctly.
Derive state IDs from `prefix` (multi-instance safe).

### [x] 10. `commands` / `exec` block — run ordered commands
**Resolved 2026-06-18.**

Outcome note: added a generic `commands` block with tested `select_commands`
filtering (`phase`, `when_set`, malformed-entry skip), pre/post-systemd
dispatch ordering, and Grafana's `reset_admin_password` as preset data fed by a
semantic top-level `admin_password` via stdin. Commands do not feed the restart
`changed` contract; entries should use `unless`/`onlyif` when they need
idempotency.

**Where:** new `blocks/commands.sls` (or `exec.sls`); dispatched from `init.sls`.

**Why:** Things like `grafana-cli plugins install …`, one-shot migrations, cache
warms. Currently no generic way to run ordered commands as a building block.
Generic — many tools need it.

### [x] 13. `svc.data_dirs` — service-owned writable state dirs
**Implemented & validated 2026-06-18 (code + unit test; confirmed by a real
salt-ssh Grafana run). Documented in readme, pillar.example, WHITEPAPER §10.**

`fetch_archive` extracts as root with `--no-same-owner`, so anything the archive
*ships* lands root-owned, and a service that must write into archive-provided
dirs (Grafana's `data/` db, plugins, logs) can't. (VL/VM don't hit this — their
writable `storageDataPath` doesn't exist post-extract, so the service creates it
under the user-owned `install_dir` itself.) Added an optional `svc.data_dirs`
list: after extraction, each is `File.directory`'d owned by the service user with
`recurse=[user,group]` (fixing ownership of any shipped contents). Deliberately
kept distinct from the root-owned program files (a compromised service can't
rewrite its own binary) and **not** added to the `changed` restart-trigger list
(an ownership fixup isn't a "new binary" event). Grafana preset sets
`data_dirs: ["{install_dir}/data"]` (covers db/logs/plugins — all default under
`{homepath}/data`). Pure-logic side (`expand` resolving the list through
`{install_dir}`→`{name}`) is covered by `tests/test_lib.py`; the
`File.directory`/`recurse` behavior is render-path only.

### [x] 15. Cross-instance aggregation (`gather`) — vmagent scrape configs
Implemented 2026-06 as explicit scrape collection, without a new render block.
The `vmagent` preset sets `scrape_collect:
config:promscrape.yml:contents:scrape_configs`; producer presets can declare
literal `scrape` jobs targeting `scrape.vmagent` globs. See
`docs/extending-with-app-blocks.md` → "Cross-instance aggregation".

A consumer (vmagent) renders one config gathered from other instances' pillar
(exporters declare `scrape`). Settled: **pull not push** (stateless,
order-independent, orphan-free); **selector-scoped** with `vmagent` globs;
contributions **literal** in v1 (no cross-scope expansion / flag-parsing);
**host-local**; verbatim job dicts with duplicate `job_name` render failures;
**no magic placeholder** in `expand`. First feature where one instance reads
others — flagged in WHITEPAPER §10.

---

### [ ] 18. App-management blocks (post-rename roadmap)
Order, each step deployable on its own (target: moituristy mt-crm):
1. [x] foundations (done) - `{home}` placeholder, `sources` block (`git.latest`,
   or `git.cloned` for `once: true`), `commands.onchanges` (replaces the
   `hook:` idea; composes with `phase`), `dirs` block, `cron` block, plus a
   systemd guard (managed unit without ExecStart now fails the render). Not
   yet verified by a real apply (Git/Cron state names, second-run
   idempotency).
2. [x] `php_fpm.pools` map (pools only, reload per version on change) +
   `nginx.vhosts` keyed map with built-in or custom jinja templates (breaking:
   the old single-vhost `nginx.{vhost_name,upstream,servers,auth_basic}` now
   fails loud; migrate to `nginx.vhosts.<key>` with `name:` to keep the file
   and ACME cert path). Also: a `config` entry inside a `sources` target now
   `require`s that source, and a `dirs` entry inside a source target fails
   loud (found in production: a failed clone + makedirs left a non-empty
   non-repo target that every later `git.cloned` refused). Not yet verified by
   a real apply (pool reload, vhost render through Salt, `require` on the
   config entry), only by unit tests and a standalone jinja render.
3. [x] `nvm`, `pyenv`, `tools` (composer) + a generated env file (`env_sh`),
   per-user when `user.name` is not root, global when it is; new phase-2
   placeholders `{nvm_dir}`, `{pyenv_root}`, `{tools_dir}`, `{env_sh}`. Not
   verified by a real apply (only unit tests and a fake-state emit): assumes
   `nvm version <v>` prints `N/A` when absent, that the pinned tags
   (nvm v0.40.1, pyenv v2.4.0) exist, and that File.prepend / makedirs
   ownership behave as expected.
4. `docker` (networks, registry login via stdin, containers, container cron
   as root `docker exec` without `-it`).

### [x] 21. Several systemd units per instance + pillar-format compat checks (0.2)
**Resolved:** `systemd.units.<unit>` keyed map, merged over `systemd.defaults`;
unit `name` defaults to `appsvc_{name}_{unit}`, bundled presets pin
`appsvc_{name}` (renders byte-identical to 0.1, so no fleet restart);
`delete: true` removes a unit, dropping it from pillar leaves it alone; unit
names checked unique across instances, distro names rejected. `compat.py`
recognises old pillar shapes (0.2 systemd, 0.1 nginx single-vhost, moved out of
lib.py) and fails with a pointer into CHANGELOG.md. Decided: no schema
version in pillar - shape detection is more precise.
Not done: **user units** (`systemctl --user`: `~/.config/systemd/user`,
`XDG_RUNTIME_DIR=/run/user/<uid>` with runas, `loginctl enable-linger`; Salt's
service states don't cover them) - a later per-unit `scope: user` fits this
shape.

### [x] 22. Split lib.py by area
**Resolved:** the ~2k-line `lib.py` became `lib/{core,release,app,runtimes,
web,systemd}.py` (pure move, no behavior change), each depending only on
`core.py`, with one `tests/test_<module>.py` each. Modules import `core.py` with
pyobjects' `from salt://appsvc/lib/core.py import ...`; `tests/conftest.py`
serves `lib/` to pytest as the package `appsvc_lib`, rewriting only those lines.
Older items below that say `lib.py` / `tests/test_lib.py` predate the split.

### [ ] 20. Gaps left by app-management step 2
- [x] **logrotate** for app logs - done: `blocks/logrotate.sls` composes one
  `/etc/logrotate.d/appsvc-<instance>` from the declared pool/vhost logs.
- **ACME webroot accounts**: only DNS accounts work (the vhost needs the cert
  files before `nginx -t`; there is no snakeoil first pass for webroot
  validation).
- **php-fpm reload on code change** (opcache) is not done: pool reload is
  `onchanges` of the pool file only; deploys own reloading after a release.

### [x] 19. Remove the binsvc -> appsvc compatibility shims
**Resolved:** removed - every client pillar was renamed to `appsvc:` and every
host applied once, so nothing reads the old `binsvc:` pillar root or needs the old unit
cleanup any more. The shims were: `init.sls` falling back to the legacy `binsvc:`
pillar root, and `blocks/systemd_unit.sls` stopping/removing a leftover pre-rename
`binsvc_<name>.service` before starting `appsvc_<name>`.
One-time side effects of the rename on a legacy host: the service restarts
under its new unit name, archives re-download into `/var/cache/salt/appsvc`
(the old `/var/cache/salt/binsvc` is left behind - safe to delete), version
stamps and venv digests change file names so each re-extracts/rebuilds once.

## Resolved / decisions on record (do not relitigate)

- **[x] Scope widened: services AND applications (renamed binsvc -> appsvc).**
  Supersedes the kickoff decision "service-mgmt of prebuilt binaries, NOT
  app-mgmt; PHP-FPM/LEMP out of scope". What changed: real apps are
  multi-runtime (php-fpm + node, python + node, + docker, + a userspace
  daemon) and `app.*`'s one-type-per-app shape can't express them as one
  unit, while key-presence block dispatch can. The old warning still binds
  the *how*: php-fpm/app features are their own blocks, never squeezed
  through `svc`/`systemd_unit`. Agreed shape (see TODO 18):
  - one instance = one unix user and everything it owns; `svc` stays optional
    (apps usually omit it).
  - every multi-valued app key is a **keyed map**, not a list (php pools,
    nginx vhosts, git sources, tools, cron) - `merge` replaces lists
    wholesale, so only maps let a preset ship a default the pillar tweaks.
  - **portable**: no includes of / dependencies on other formulas in this
    repo. Installing nginx, php-fpm, docker is their own states' job; external
    contracts (acme.sh `verify_and_issue.sh` path) are documented, not imported.
  - php-fpm: appsvc manages **pools only**, never PHP installation. Reload
    `php{ver}-fpm` strictly `onchanges` of the pool file (`app.php-fpm`
    reloads on every apply, which is why pillars there set `reload: False`).
  - pyenv/nvm: per-user when `user.name` isn't root, global when it is.
  - composer etc.: a generic `tools:` map of single-file downloads (reusing
    fetch's `kind: file`), not per-tool blocks.
  - queue workers stay under supervisor (dozens of processes, numprocs).
    Superseded in part (0.2): an instance may run a few systemd units
    (`systemd.units`, e.g. a main daemon + a consumer); large numproc worker
    pools still belong to supervisor.
  - no migration from `app.*` is planned; both live indefinitely.

- **[x] GitHub resolvers read releases, not `/tags`.**
  `/tags` is unsorted and can return tags never published as releases. The
  default `github` resolver uses `/releases/latest`; `github_versionsort` lists
  releases and picks the highest semver-like tag for repos with LTS latest
  pointers. See `lib.py` release section + `WHITEPAPER.md` §10.
- **[x] `merge` replaces lists wholesale; `svc.args` is the one exception**
  (structured args merge by flag name via `merge_args`; raw string args replace
  wholesale and render as-is). Not generalized into `merge` because the
  "ordered list of single-key mappings" shape isn't universal. See
  `WHITEPAPER.md` §10.
- **[x] Two-phase `expand`, no phase 3.** If tempted to add a phase or a new
  cross-referencing placeholder, prefer computing the value *inside* the block
  that needs it (like `{file}` in `fetch_archive`). See `WHITEPAPER.md` §5.
