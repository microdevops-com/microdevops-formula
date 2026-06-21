# Extending binsvc: app-specific management (the "Grafana datasources" problem)

When a tool needs more than fetch + systemd + a config file — e.g. Grafana
wants provisioned datasources/dashboards, an edited `grafana.ini`, installed
plugins, maybe API-driven setup — the instinct is "write a Grafana module."
Usually that's the wrong first move. This note records *how* to extend binsvc
for app-specific management without breaking what the design bought you.

Read `WHITEPAPER.md` first (esp. §3 logic/directives split, §6 the
`changed`/`watch` contract). For live gaps referenced here, see `TODO.md`.

## The governing principle

binsvc splits three things on purpose:

- **generic mechanism → code** (`blocks/*.sls` + `lib.py`)
- **app-specific knowledge → data** (`presets/*.yaml`, pillar)
- **irreducible app-specific logic → code**, but *thin* and contract-following

Most "extended management" is not app *logic* — it's app *data* (paths,
content) riding on a mechanism you either already have or should add
**generically**. So the decision is never "module: yes/no." It's: decompose
the need into primitives, then route each primitive by the litmus test below.

## Litmus test (apply per primitive, not per app)

1. **Expressible as data over an existing/generic block?** → preset/pillar only,
   **no code**.
2. **Needs a new mechanism other tools would also want?** → add a **generic
   block**, not an app block.
3. **Needs genuinely app-specific logic** (HTTP-API upsert, app-specific
   ordering/validation, a nicer pillar API that takes real translation)? → a
   **thin app block** (`blocks/<app>.sls`) that composes generic blocks and puts
   pure logic in `lib.py`.

The failure mode to avoid: a fat app module that re-implements fetch/systemd/
config or bakes in behavior other tools also need. That's exactly
`application/`'s hardcoded `vmagent()` one-off — the thing binsvc exists to kill.

## Worked decomposition: "extended Grafana management"

| Need | What it really is | Route |
|---|---|---|
| Provision datasources | YAML files in `/etc/grafana/provisioning/datasources/` | generic `config_dir` (N files) → preset data |
| Provision dashboards | provider YAML + dashboard JSON files | generic `config_dir` → preset data |
| Edit `grafana.ini` | render an INI file | `config_file` with `format: ini` |
| Install plugins | `grafana-cli plugins install …` | generic `commands` block |
| API provisioning | idempotent upsert via Grafana HTTP API, after start | thin `blocks/grafana.sls` + pure `lib.py` helpers |

Note the shape: only the **last row** is Grafana *code*. The rest is Grafana
*data* over mechanisms that aren't Grafana-specific at all (Loki, Prometheus,
Alertmanager will want the same `config_dir` / `commands` / INI capabilities).

## Recommended order of work

1. **Fill the generic gaps first** (these are missing vocabulary, not app work):
   - `config_dir` — render N files into a directory, return the `changed`
     contract. Covers any tool with a provisioning/conf.d directory.
   - `commands` / `exec` — done in binsvc: run ordered pre/post commands with
     `when_set`, `unless`/`onlyif`, and `stdin`. Covers `grafana-cli`, cache
     warms, one-shot migrations.
   - TOML output for `config_file` only if a real consumer needs it; INI/JSON/YAML are already covered.
   After these, ~80% of "extended Grafana management" is **preset/pillar data
   over generic blocks, zero Grafana code**.
2. **Add a thin app block only for the residue.** If you want a friendly pillar
   API (`grafana: { datasources: [...], dashboards: [...] }`) or HTTP-API
   provisioning, add `blocks/grafana.sls`:
   - signature `grafana_provision(prefix, settings)`, same as every block;
   - derive all state IDs from `prefix` (multi-instance stays free);
   - reuse `config_dir`/`config_file` for file work — don't re-emit raw
     `File.managed` it could delegate;
   - put real logic (defaults, validation, API payload building, idempotent
     upsert decisions) in **pure `lib.py` functions** so it's unit-tested
     without a minion;
   - **return the `changed` list** so restart/reload threads correctly (§6).

## Two core changes this requires

### 1. An app-block registry in `dispatch`

`dispatch` currently runs a *fixed* block list. App blocks should slot in via
an app-block registry: run a `grafana` block when `settings` has a `grafana:`
key (mirroring how nginx/systemd already run on key presence / `manage: true`).
This generalizes — a future `loki:` / `prometheus:` block registers
identically. Keep it data-driven (key → handler), not a growing `if/elif`
chain.

### 2. The systemd-ordering contract (do not gloss over this)

App provisioning is **not a single slot**. It splits around service start:

- **File-based provisioning** (datasources/dashboards/ini) must land **before**
  `systemd_unit` starts the service — Grafana reads `provisioning/` at boot.
- **API-based provisioning** and anything needing a *running* server
  (`grafana-cli` against the live instance, HTTP upserts) must run **after**.

So the dispatch contract for app blocks should let a block declare a
pre-systemd phase and a post-systemd phase (e.g. two functions, or a phase
arg), rather than assuming one position. Decide this explicitly up front —
discovering it later means an API-provisioning step that silently races
startup and "works on my machine."

Current fixed order, for reference (§6):

```
user_and_ssh → config_files → fetch_archive → commands(pre)
  → systemd_unit → commands(post) → nginx_vhost
                    │                    │
        pre-systemd app phase here        post-systemd app phase here
```

## Cross-instance aggregation (one instance reads others)

Some consumers need config assembled *from other instances* — e.g. a `vmagent`
that scrapes the exporters on the same host: each exporter declares how it should
be scraped, and vmagent renders one config gathering them. (The legacy answer was
a `scrape_configs.d/*.yml` glob each exporter dropped a file into.) This is
implemented for vmagent via `collect_scrape_jobs`, `append_at_path`, and the
consumer's `scrape_collect` colon path; no app-block registry was needed for v1.

- **Pull, not push; static facts, not a shared variable.** Producers (exporters)
  declare a static key in their own pillar; the consumer (vmagent) *pulls* and
  merges at render. This is **stateless and apply-order-independent** — the key
  win over the file-glob (which raced on first run and left orphaned files when an
  exporter was removed). Do **not** model it as a mutable "global variable both
  sides write" — that reintroduces ordering/state. Removing a producer from pillar
  removes its contribution, automatically.

- **Generalize only what is real.** The implemented reusable pieces are
  `collect_scrape_jobs(merged_instances, consumer_name)` and
  `append_at_path(container, path, items, unique_key="job_name")`. The former
  scans merged instance settings for the known `scrape` shape; the latter handles
  the list append at the consumer's configured path. No pub/sub framework, no
  `provides` envelope, no generic merge strategy. Only generalize further if a
  second consumer needs a different contribution shape.

- **Selector-scoped, never "scan all".** "Collect every scrape job" assumes one
  vmagent per host, which contradicts binsvc's multi-instance reason for being.
  Producers declare `scrape: {vmagent: <scalar-or-list-of-globs>, config: [...]}`;
  `vmagent` is required when `scrape` is present, and a consumer gathers only
  what matches its instance name. Matching nothing is a no-op.

- **Contributions are literal (v1).** A value gathered from instance X's *raw*
  merged settings is **not** expanded in X's scope. `init.sls` does a two-pass
  loop: pass 1 merges every instance, pass 2 resolves/expands the consumer and
  injects gathered jobs after expansion. So author scrape targets concretely
  (`targets: ["127.0.0.1:9100"]`); don't reference X's `{install_dir}`/`{args}`.
  Do **not** derive the target by parsing X's listen flag — exporters disagree
  (`-httpListenAddr` vs `--web.listen-address`); that's the silently-tool-specific
  trap. (v2, if wanted: expand each source in its own scope before gathering.)

- **Host-local by design.** Pillar-scan sees only this minion's `binsvc:instances`
  (same boundary the file-glob had). Remote scrape targets go directly in the
  consumer's own config.

- **Store the contribution verbatim; ensure key uniqueness.** `scrape.config` is
  a list of Prometheus/VM scrape-job dicts; "how often/how" is just job fields
  (`scrape_interval`, `metrics_path`, …). `append_at_path(...,
  unique_key="job_name")` fails the render if the final list has duplicate job
  names, including duplicates between base config and gathered jobs.

- **No magic placeholder.** Don't weave gathering into `expand` (e.g.
  `scrape_configs: {{ gathered(...) }}`). Keep it an explicit consumer-block step;
  `expand` stays pure and local.

- **Flag the non-locality when built.** This is the first place vmagent's config
  *can't be understood from vmagent's own pillar* — you must scan every instance
  (Puppet exported-resources-style "action at a distance"). Acceptable, but contain
  it: explicit + selector-scoped, and call it out in `WHITEPAPER.md`. This is now
  recorded there.

## Why not a parallel formula

Running a separate Grafana state alongside binsvc throws away the merge/expand
pipeline, the `changed`/`watch` restart contract, and `prefix`-based
multi-instance — you'd hand-reimplement orchestration and slide back into the
one-instance-per-host pattern binsvc was built to kill. Grafana is fetch +
systemd + config + provisioning: almost entirely binsvc's wheelhouse. Reserve
"separate formula" for something that shares *nothing* with binsvc (the repo's
existing Docker-based `grafana/` formula is a different deployment model, not
"extended management" — not a counterexample).

## Summary

Extend, don't fork. Generic gap → generic block. App knowledge → preset data.
Only irreducible app logic → a thin app block (dispatched via an app-key
registry, honoring the `changed`/`watch` contract and the pre/post-systemd
ordering, with pure logic in `lib.py`).
