# binsvc — TODO / open concerns

Stable tracker for known issues and follow-ups. Survives context compaction
and new sessions. Update the status box when something is done; don't delete
items — strike them or mark `[x]` with a one-line resolution note so the
history of *why* a decision was made stays visible.

Status legend: `[ ]` open · `[~]` in progress · `[x]` done · `[-]` won't do (with reason)

Source: code review on 2026-06-09 (Opus) of the binsvc state. Each item lists
**why** it matters and **what** to do, with file references.

---

## P1 — architecture / correctness

### [x] 1. Replaced the `sys.modules["lib"]` injection with per-block imports
**Resolved 2026-06-09 (spike by Sonnet, passed real render validation).**

The global `sys.modules["lib"]` injection (and its generic-name collision risk
+ in-body deferred-import boilerplate) is gone. The hypothesis held: pyobjects
runs its `from salt://...import` regex pass on **each** file as it's imported,
so a block carrying its *own* top-line `from salt://binsvc/lib.py import <names>`
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
- Optional `binsvc:github_token` (top-level pillar) → Bearer auth on the github
  resolver only (never sent to grafana.com, kept out of the cache key); lifts
  GitHub to 5000 req/hr. This is the mitigation for the **NAT unhappy path**
  (minions rendering locally behind a shared egress IP don't share the cache
  filesystem).

Tests in `tests/test_lib.py`; documented in WHITEPAPER §10, `defaults.yaml`,
`pillar.example`. Render/concurrency path itself is render-only (not unit-tested).

### [ ] 3. Binaries are fetched unverified by default
**Where:** `presets/victorialogs.yaml`, `presets/victoriametrics.yaml`
(`svc` has no `source_hash`); `blocks/fetch_archive.sls` falls back to
`skip_verify=True` when no `source_hash` is given.

**Why:** Supply-chain footgun — VL/VM binaries download with no integrity
check by default. The `vm_main` *pillar example* uses VM's published
`_checksums.txt`, but the *presets* don't, so the secure path is opt-in.

**What to do:** Add a derivable `source_hash` URL to the github presets so
verification is the default. (VM publishes `..._checksums.txt` alongside each
release archive.)

### [x] 11. Remove `store`; introduce `version_resolver` (archive-only)
**Resolved 2026-06-18.**

Outcome note: binsvc is archive-only; `store`/`FETCH_HANDLERS`/`fetch_package`
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
flips to binsvc-managed systemd (tarball has no postinst, so `systemd.manage`
goes true + the preset gains a `systemd:` section); WHITEPAPER §4/§8/§10 + readme
need updating *as part of the change* (don't pre-edit — keep doc/code in sync).

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
describes blocks carrying their own top-level `from salt://binsvc/lib.py import`
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

### [ ] 6. `config_file` is YAML-centric but named broadly
**Where:** `blocks/config_file.sls` (`yaml.safe_dump` of `contents`).

**Why:** grafana.ini / prometheus / loki want INI/TOML, not YAML. The name
promises more than the body delivers. Documented as narrow, but the gap will
bite whoever adds a TOML/INI-config service.

**What to do:** Either support a `format:` hint (yaml/ini/toml/raw) or rename to
signal the YAML/source-only scope. Low priority until a non-YAML service needs it.

### [ ] 7. nginx basic-auth secrets in plaintext pillar, rewritten every run
**Where:** `blocks/nginx_vhost.sls` (`Webutil.user_exists(..., force=True)`),
`pillar.example` (`password: change-me`).

**Why:** Passwords live in pillar plaintext; `force=True` rewrites the htpasswd
entry on every run.

**What to do:** Add a note in `pillar.example` that auth_basic credentials
belong in secured/encrypted pillar. (Behavioral change optional.)

### [ ] 8. Working-tree `.pyc` / pytest cache
**Where:** `binsvc/__pycache__/lib.cpython-311.pyc`,
`binsvc/tests/__pycache__/`, `binsvc/.pytest_cache/`.

**Why:** `.gitignore` covers `__pycache__/` and `.pytest_cache/`, so they won't
be committed — but they're sitting in the working tree. Cosmetic.

**What to do:** Nothing required; optionally `git clean`-ignore is already
handled. Verify they're absent from the first commit.

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
data over generic blocks, with no app-specific code. Together with #6
(INI/TOML output for `config_file`) they form the vocabulary an app block
would compose.

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

### [ ] 10. `commands` / `exec` block — run ordered commands
**Where:** new `blocks/commands.sls` (or `exec.sls`); dispatched from `init.sls`.

**Why:** Things like `grafana-cli plugins install …`, one-shot migrations, cache
warms. Currently no generic way to run ordered commands as a building block.
Generic — many tools need it.

**What to do:** A block running an ordered list of commands with
`onchanges`/`unless`/`cwd`/`runas` support, returning the `changed` contract.
Mind the systemd-ordering split (`docs/extending-with-app-blocks.md`): some
commands must run *before* service start, some *after* (need a running
service) — design the phase handling alongside the app-block dispatch registry.

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

---

## Resolved / decisions on record (do not relitigate)

- **[x] Scope: service-mgmt of prebuilt binaries/packages, NOT app-mgmt.**
  PHP-FPM/LEMP is deliberately out of scope. Unifying "download a binary" with
  "deploy a PHP app with fpm pools" would produce a worse abstraction. Keep
  them separate. (Original open question from project kickoff — resolved by the
  shape the code took.)
- **[x] "latest" resolves via GitHub `/releases/latest`, not `/tags`.**
  `/tags` is unsorted and (for VictoriaMetrics/VictoriaLogs) returns tags never
  published as releases — silently picks a wrong, higher-looking version. The
  tags-based path was removed entirely rather than left as a trap. See
  `lib.py` release section + `WHITEPAPER.md` §4. Don't "simplify" this back.
- **[x] `merge` replaces lists wholesale; `svc.args` is the one exception**
  (merged by flag name via `merge_args`). Not generalized into `merge` because
  the "ordered list of single-key mappings" shape isn't universal. See
  `WHITEPAPER.md` §10.
- **[x] Two-phase `expand`, no phase 3.** If tempted to add a phase or a new
  cross-referencing placeholder, prefer computing the value *inside* the block
  that needs it (like `{file}` in `fetch_archive`). See `WHITEPAPER.md` §5.
