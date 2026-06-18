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
| Edit `grafana.ini` | render an INI file | `config_file` + an INI/TOML `format:` hint (TODO #6) |
| Install plugins | `grafana-cli plugins install …` + restart | generic `commands`/`exec` block |
| API provisioning | idempotent upsert via Grafana HTTP API, after start | thin `blocks/grafana.sls` + pure `lib.py` helpers |

Note the shape: only the **last row** is Grafana *code*. The rest is Grafana
*data* over mechanisms that aren't Grafana-specific at all (Loki, Prometheus,
Alertmanager will want the same `config_dir` / `commands` / INI capabilities).

## Recommended order of work

1. **Fill the generic gaps first** (these are missing vocabulary, not app work):
   - `config_dir` — render N files into a directory, return the `changed`
     contract. Covers any tool with a provisioning/conf.d directory.
   - `commands` / `exec` — run ordered commands with `onchanges`/`unless`,
     return `changed`. Covers `grafana-cli`, cache warms, one-shot migrations.
   - INI/TOML output for `config_file` (TODO #6).
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
user_and_ssh → config_files → fetch_archive → systemd_unit → nginx_vhost
                    │                                  │
        pre-systemd app phase here          post-systemd app phase here
```

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
