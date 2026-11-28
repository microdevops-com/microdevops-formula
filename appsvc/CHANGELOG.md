# appsvc changelog

Pillar-format changes, newest first. A **breaking** entry changes the shape of
existing pillar. `compat.py` recognises the old shape and fails the render with
a pointer to the entry's anchor, e.g.
`[0.2, appsvc/CHANGELOG.md#0.2-systemd-units]`. Additive changes (new keys, new
blocks) are listed briefly and need nothing from existing pillar.

The version exists only here; there is no version field in pillar. A check
recognises the old shape itself, which says more than a version number could.

## 0.2

<a id="0.2-install-dir"></a>
### Breaking: `install_dir` has no default

`defaults.yaml` no longer sets `install_dir: "/opt/services/{type}/{name}"`. A
forgotten `install_dir` (most web apps live in `/var/www/{name}/app`) used to
land there silently. Every bundled preset now sets it explicitly, so
preset-based instances render as before. An instance without a preset must set
it, and the render fails if neither the preset nor the instance does.

```yaml
# before: no install_dir, got /opt/services/{type}/{name}
mt-argon:
  user: {manage: true, name: argon}

# after
mt-argon:
  install_dir: /var/www/{name}/app           # or the old path, to keep it
  user: {manage: true, name: argon}

# an instance with no directory of its own (cron-only, nginx-only, ...)
cleanup:
  install_dir: null
```

With `install_dir: null`, the render fails where an applied setting still
uses `{install_dir}`: a systemd unit's `WorkingDirectory` (the default is
`{install_dir}`, so set your own), `venv.manage`, a `kind: archive` `svc` or
a `kind: file` one without `svc.target`, or any of your own values.

<a id="0.2-systemd-units"></a>
### Breaking: one instance, several systemd units (`systemd.units`)

An instance now owns a keyed map of units instead of exactly one.
`systemd.{Unit,Service,Install}` moved under `systemd.units.<unit>`, and
`systemd.unit` (the unit-name override) became `systemd.units.<unit>.name`.

- The key (`<unit>`) identifies the unit for merging and is the `{unit}`
  placeholder. `name` is the systemd unit name, with or without `.service`. It
  defaults to `systemd.defaults.name: "appsvc_{name}_{unit}"`.
- `systemd.defaults.{Unit,Service,Install}` (from `defaults.yaml`) are merged
  under every unit. `{unit_name}` is the resolved name, usable inside the
  unit's sections.
- **Bundled presets** define one unit, `main`, with `name: "appsvc_{name}"`, so
  their units keep the old name and the same file contents. Nothing restarts
  on upgrade.
- Every kept unit restarts when the instance's code, binary, config or
  runtimes change (the `changed` contract), as the single unit did.
- `delete: true` stops, disables and removes a unit once. A unit that is only
  dropped from pillar is left alone (not managed).
- An instance with no units does nothing. `systemd.manage: false` is no longer
  required for a daemon-less app, but still works and turns off all of the
  instance's units.
- Fails the render: two instances (or two keys of one instance) resolving to
  the same unit name; a name with another unit suffix (`.timer`, ...), an
  `@`, or braces from an unresolved placeholder; a distro service name
  (`nginx`, `php*-fpm`, `redis-server`, ...) that a file in
  `/etc/systemd/system` would override.

Before:

```yaml
appsvc:
  instances:
    vmagent_main:
      preset: vmagent
      systemd:
        Service:
          LimitNOFILE: 65536
    worker:
      systemd:
        unit: my-worker
        Service:
          ExecStart: /opt/worker/bin/run
```

After:

```yaml
appsvc:
  instances:
    vmagent_main:
      preset: vmagent
      systemd:
        units:
          main:                   # the bundled preset's unit key
            Service:
              LimitNOFILE: 65536
    worker:
      systemd:
        units:
          main:
            name: my-worker       # was systemd.unit (without it, the old name was "appsvc_{name}")
            Service:
              ExecStart: /opt/worker/bin/run
          consumer:               # -> appsvc_worker_consumer.service
            Service:
              ExecStart: /opt/worker/bin/consume
```

Detected by: `systemd.Unit`, `systemd.Service`, `systemd.Install` or
`systemd.unit` in an instance or a pillar preset.

Also in 0.2 (additive):

- `appsvc:filter` takes a `block:` clause (`"name: mt-argon; block: cron"`)
  that applies only those blocks. Without `name`/`preset` it covers every
  instance.
- `nvm.build_pkgs` (default `[git, curl]`). `pyenv.build_pkgs` gained `git`,
  `curl` and `libzstd-dev`.
- Logs moved under `log:` - `nginx.vhosts.<key>.log.{access,error}` (was
  `access_log`/`error_log`) and `php_fpm.pools.<key>.log.error` (was
  `error_log`). New: `log.slow` (php-fpm slowlog) with `log.slow_timeout`
  (default 10 s) and `log.slow_trace_depth` (default 0); slow logs join the
  logrotate file. The old keys now fail as unknown keys.
- `nginx.defaults` / `php_fpm.defaults`: merged under every vhost / pool,
  like `systemd.defaults`, so a preset can set logs (or a version, a
  template, ...) for all of them. Placeholders `{vhost}`/`{vhost_name}`,
  `{pool}`/`{pool_name}`/`{php_version}`. A pool may be empty (`back:`).
  `{version}` in a pool `listen` is now `{php_version}` (`{version}` is
  `svc.version` and was already expanded away before the pool saw it).
- `install_dir` and `user.home` also take a mapping, `{name, group, mode}`
  (`install_dir` also takes `user`). A plain path string still works and
  behaves as before. Use it for per-site isolation: `750 <user>:www-data` on
  the site's top directory lets nginx in and keeps other site users out. The
  render fails if a managed user is in the group guarding another instance's
  directory (see readme, "Directory isolation"). Layers merge key by key (a
  path string counts as `{name: <path>}`), so a preset's `{group, mode}`
  survives an instance's plain path.

## 0.1

The first settled format: `binsvc` renamed to `appsvc` and widened to app
management (sources, dirs, cron, php-fpm pools, nvm/pyenv/tools, env_sh,
nginx vhosts, logrotate). Commit `f5801f2`.

<a id="0.1-nginx-vhosts"></a>
### Breaking: nginx vhosts are a keyed map (`nginx.vhosts`)

The single-vhost `nginx.{vhost_name,upstream,servers,auth_basic}` became
`nginx.vhosts.<key>`, one entry per server group.

Before:

```yaml
nginx:
  manage: true
  vhost_name: grafana
  upstream: 127.0.0.1:3000
  servers:
    - names: [grafana.example.com]
      acme_account: example_com
```

After:

```yaml
nginx:
  manage: true
  vhosts:
    grafana:
      name: grafana               # keeps the sites-available file and the ACME cert
      upstream: 127.0.0.1:3000
      names: [grafana.example.com]
      acme_account: example_com
```

Detected by: `nginx.upstream`, `nginx.servers`, `nginx.vhost_name` or
`nginx.auth_basic` in an instance or a pillar preset.
