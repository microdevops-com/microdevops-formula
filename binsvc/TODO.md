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

### [ ] 2. `resolve_latest` does unbounded network I/O at render time
**Where:** `lib.py` `resolve_latest()` (the `requests.get(url)` call).

**Partial 2026-06-18:** `_get_json()` now calls `requests.get(...,
timeout=10)`, covering the timeout part for GitHub and Grafana resolvers.
Token/auth, render-time coupling docs, and caching remain open.

**Why:** Runs during *rendering*. No timeout → a hung GitHub socket hangs the
whole render. No auth → unauthenticated GitHub API is 60 req/hr/IP; a master
rendering many minions or frequent highstates will hit the limit and fail the
*render* (not just serve a stale version). If GitHub is down the instance
fails to compile.

**What to do:**
- Support an optional GitHub token (env var or pillar) to lift the 60/hr cap.
- Document that `version: latest` couples render to a third-party API; pinning
  is the safe default. Consider caching the resolved tag per run.

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

### [ ] 12. Verify grafana preset against a real tarball (homepath / unpack dir)
**Where:** `presets/grafana.yaml`. Found during review of the item-11
implementation, 2026-06-18. These only surface at *runtime* — a render won't
catch either.

**Why:**
- **`--homepath` likely wrong.** `svc.exec` runs `{install_dir}/bin/grafana` and
  `WorkingDirectory` is `{install_dir}` — both consistent with `tar.args:
  --strip-components 1` (archive contents land at install_dir root). But the same
  exec passes `--homepath={install_dir}/grafana`, a subdir that won't exist after
  a strip-1 extract, so Grafana won't find `conf/`/`public/`. Almost certainly
  should be `--homepath={install_dir}`. The binary-path and homepath assume
  different layouts — they can't both be right.
- **`tar.unpack: "grafana-{tag}"` unconfirmed.** Assumes the tarball's top dir is
  `grafana-<version>` (no `v`). If it's actually `grafana-v<version>` or similar,
  `--strip-components 1` + member-extraction silently extracts nothing → empty
  install_dir.

**What to do:** Download one resolved tarball; confirm the top-dir name and the
`bin/`/`conf/`/`public/` layout; fix `homepath` (and `unpack` if needed). Also
confirm `grafana -version` works for `fetch_archive`'s `version_check` unless-guard
(ties to #5 — `version_check` assumes `binary -version`).

---

## P2 — docs / honesty

### [ ] 4. Stale docstring in `lib.py` still asserts the old (wrong) globals story
**Where:** `lib.py` module docstring, ~lines 4–5: "...makes every function
available in block files' `__globals__` automatically since lib is imported
before blocks."

**Why:** This is the *old, incorrect* claim already corrected in `WHITEPAPER.md`
and `readme.md` this session. The frozen-globals snapshot means it was never
true; the actual mechanism is the `sys.modules` injection (see item 1).

**What to do:** Fix the docstring to describe the real mechanism (or, if item 1
lands the per-block-import approach, describe *that*). Keep it short.

### [ ] 5. Trim doc-to-code ratio; temper "generic reusable lib" framing
**Where:** `WHITEPAPER.md` (440 lines for ~600 lines of code), §10's
"future application/ rewrite" framing.

**Why:** Heavy prose drifts out of sync (item 4 is proof). Also, only
`expand`/`merge`/`render_unit`/`join_args` are genuinely generic — `lib.py`'s
fetch/release helpers are domain-specific: `latest_from_release` hardcodes VM's
`-cluster` strip, `repo_from_source` assumes a github.com URL shape,
`version_check` assumes `binary -version` grep-able output.

**What to do:** Lean WHITEPAPER toward "decisions + gotchas," let tests document
behavior. State plainly that the reusable surface for any future app-mgmt
rewrite is the *pipeline shape* (merge→expand→dispatch + the `changed`
contract), not the fetch/release helpers.

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
