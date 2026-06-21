#!pyobjects
# vim: set ft=python:

# binsvc: run N instances of a statically-built binary
# (VictoriaMetrics, VictoriaLogs, Grafana, Loki, Prometheus, exporters, ...)
# under systemd, each independently configured from one merged
# defaults -> preset -> instance settings dict. See readme.md for the full
# pillar shape and binsvc/lib.py's docstring for the design rationale.

import logging
import yaml

from salt://binsvc/lib.py import append_at_path, collect_scrape_jobs, expand, join_args, merge, merge_args, normalize_osarch, resolve_latest

from salt://binsvc/blocks/fetch_archive.sls import fetch_archive
from salt://binsvc/blocks/user_ssh.sls import user_and_ssh
from salt://binsvc/blocks/config_file.sls import config_files
from salt://binsvc/blocks/commands.sls import run_commands
from salt://binsvc/blocks/systemd_unit.sls import systemd_unit
from salt://binsvc/blocks/nginx_vhost.sls import nginx_vhost
from salt://binsvc/utils.sls import get_salt_file

log = logging.getLogger(__name__)


# --- defaults & presets -------------------------------------------------------
#
# get_salt_file (binsvc/utils.sls) uses salt.fileclient directly and works
# under salt-ssh. __salt__["cp.get_file_str"] does not work there.

DEFAULTS = yaml.safe_load(get_salt_file("salt://binsvc/defaults.yaml") or "") or {}

_preset_cache = {}


def load_preset(name):
    """Lazily load & cache a bundled preset (salt://binsvc/presets/{name}.yaml),
    deep-merged with any pillar override at binsvc:presets:{name}. Presets ship
    with the formula so instances only need to override what differs, instead
    of copying whole app configs into pillar. A preset name with no matching
    bundled file is treated as empty - only the pillar override applies."""
    if name not in _preset_cache:
        _content = get_salt_file("salt://binsvc/presets/{}.yaml".format(name))
        bundled = yaml.safe_load(_content or "") or {}
        override = pillar("binsvc:presets:{}".format(name), {})
        _preset_cache[name] = merge(bundled, override or {})
    return _preset_cache[name]


# --- "latest" version resolution ---------------------------------------------

def resolve_latest_version(svc_settings):
    """Delegate version/source resolution to lib.py's named resolver registry.
    Passes the shared resolve-cache config (DEFAULTS, not per-instance: the cache
    is keyed by API URL and shared across instances/minions on the render host)."""
    context = {
        "osarch": normalize_osarch(grains("osarch") or ""),
        "cache_dir": DEFAULTS.get("cache_dir"),
        "resolve_cache_ttl": DEFAULTS.get("resolve_cache_ttl", 0),
        "github_token": pillar("binsvc:github_token", None),
    }
    return resolve_latest(svc_settings, svc_settings.get("version_resolver", "github"), context)


# --- building-block dispatch --------------------------------------------------


def dispatch(prefix, settings):
    """Run the building blocks an instance's merged settings call for, in a
    fixed order: user/ssh and config first (the fetch step's install_dir owner
    and systemd's restart-on-change both depend on them), then the fetch
    archive fetch, pre-systemd commands, systemd, post-systemd commands, then
    nginx. Fetch/config changes are wired via the `changed` requisite-list
    contract so systemd restarts whenever the binary or config actually
    changed."""

    user_and_ssh(prefix, settings)
    changed = list(config_files(prefix, settings) or [])

    svc = settings.get("svc")
    if svc:
        changed = list(fetch_archive(prefix, settings) or []) + changed

    run_commands(prefix, settings, phase="pre", require=changed)

    running = None
    if settings.get("systemd", {}).get("manage", True):
        running = systemd_unit(prefix, settings, watch=changed)

    run_commands(prefix, settings, phase="post", require=running)

    nginx_vhost(prefix, settings)


# --- main loop: merge all, then expand/inject/dispatch per instance ----------

instances = pillar("binsvc:instances", {})

merged = {}
for instance_name, instance in instances.items():
    preset_name = instance.get("preset")
    preset = load_preset(preset_name) if preset_name else {}

    settings = merge(DEFAULTS, preset, instance)
    settings["name"] = instance_name
    settings.setdefault("type", preset_name or instance_name)

    # Structured svc.args merge by flag name rather than replacing wholesale so
    # an instance can override e.g. just httpListenAddr from a preset's args.
    # Raw string args and repeated flags replace wholesale - see merge_args.
    preset_args = (preset.get("svc") or {}).get("args")
    instance_args = (instance.get("svc") or {}).get("args")
    if preset_args or instance_args:
        settings.setdefault("svc", {})["args"] = merge_args(preset_args, instance_args)

    merged[instance_name] = settings

for instance_name, raw_settings in merged.items():
    settings = merge(raw_settings)

    svc = settings.get("svc") or {}
    if "source" in svc:
        settings["svc"] = resolve_latest_version(svc)
        svc = settings["svc"]

    # Phase 1: resolve install_dir/source/exec against grain-derived identity
    # plus the instance's own static keys (name/type/version/tag/...).
    tag = svc.get("tag", svc.get("version", ""))
    base_scope = {
        "name": instance_name,
        "type": settings.get("type"),
        "version": svc.get("version", ""),
        "tag": tag,
        "tag_vstrip": tag.lstrip("v"),
        "osarch": normalize_osarch(grains("osarch") or ""),
        "kernel_lower": (grains("kernel") or "").lower(),
        "cpuarch": grains("cpuarch") or "",
    }
    settings = expand(settings, base_scope)

    # Phase 2: a second pass for keys only resolvable once phase 1 has
    # produced install_dir/exec/user - avoids fragile nested-placeholder
    # syntax like "{svc[exec]}" in pillar/presets.
    svc = settings.get("svc") or {}
    user = settings.get("user") or {}
    extra_scope = dict(base_scope,
                       install_dir=settings.get("install_dir", ""),
                       exec=svc.get("exec", ""),
                       args=join_args(svc.get("args", []), svc.get("args_prefix", "-") or "-"),
                       user_name=user.get("name", "root"),
                       user_group=user.get("group", user.get("name", "root")))
    settings = expand(settings, extra_scope)

    if "scrape_collect" in settings:
        jobs = collect_scrape_jobs(merged, instance_name)
        append_at_path(settings, settings["scrape_collect"], jobs, unique_key="job_name")

    dispatch(["binsvc", instance_name], settings)
