#!pyobjects
# vim: set ft=python:

# binsvc: run N instances of a statically-built binary
# (VictoriaMetrics, VictoriaLogs, Grafana, Loki, Prometheus, exporters, ...)
# under systemd, each independently configured from one merged
# defaults -> preset -> instance settings dict. See readme.md for the full
# pillar shape and binsvc/lib.py's docstring for the design rationale.

import logging
import yaml

from salt://binsvc/lib.py import expand, merge, normalize_osarch, resolve_latest, join_args, merge_args

from salt://binsvc/blocks/fetch_archive.sls import fetch_archive
from salt://binsvc/blocks/user_ssh.sls import user_and_ssh
from salt://binsvc/blocks/config_file.sls import config_files
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
    """Delegate version/source resolution to lib.py's named resolver registry."""
    context = {"osarch": normalize_osarch(grains("osarch") or "")}
    return resolve_latest(svc_settings, svc_settings.get("version_resolver", "github"), context)


# --- building-block dispatch --------------------------------------------------


def dispatch(prefix, settings):
    """Run the building blocks an instance's merged settings call for, in a
    fixed order: user/ssh and config first (the fetch step's install_dir owner
    and systemd's restart-on-change both depend on them), then the fetch
    archive fetch, then systemd - wired via the `changed` requisite-list
    contract so it restarts whenever the binary or config actually changed -
    then nginx."""

    user_and_ssh(prefix, settings)
    changed = list(config_files(prefix, settings) or [])

    svc = settings.get("svc")
    if svc:
        changed = list(fetch_archive(prefix, settings) or []) + changed

    if settings.get("systemd", {}).get("manage", True):
        systemd_unit(prefix, settings, watch=changed)

    nginx_vhost(prefix, settings)


# --- main loop: merge, expand, dispatch, per instance ------------------------

instances = pillar("binsvc:instances", {})

for instance_name, instance in instances.items():
    preset_name = instance.get("preset")
    preset = load_preset(preset_name) if preset_name else {}

    settings = merge(DEFAULTS, preset, instance)
    settings["name"] = instance_name
    settings.setdefault("type", preset_name or instance_name)

    # svc.args merges by flag name rather than replacing wholesale so an
    # instance can override e.g. just httpListenAddr from a preset's args
    # without restating storageDataPath/retentionPeriod/... - see merge_args.
    preset_args = (preset.get("svc") or {}).get("args")
    instance_args = (instance.get("svc") or {}).get("args")
    if preset_args or instance_args:
        settings.setdefault("svc", {})["args"] = merge_args(preset_args, instance_args)

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
                       args=join_args(svc.get("args", [])),
                       user_name=user.get("name", "root"),
                       user_group=user.get("group", user.get("name", "root")))
    settings = expand(settings, extra_scope)

    dispatch(["binsvc", instance_name], settings)
