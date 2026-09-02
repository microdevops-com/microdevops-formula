#!pyobjects
# vim: set ft=python:

# binsvc: run N instances of a statically-built binary
# (VictoriaMetrics, VictoriaLogs, Grafana, Loki, Prometheus, exporters, ...)
# under systemd, each independently configured from one merged
# defaults -> preset -> instance settings dict. See readme.md for the full
# pillar shape and binsvc/lib.py's docstring for the design rationale.

import logging
import yaml

from salt://binsvc/lib.py import append_at_path, collect_scrape_jobs, expand, fetch_target, join_args, merge, merge_args, merge_globals, normalize_osarch, parse_filter, resolve_latest, select_instances

from salt://binsvc/blocks/install_dir.sls import install_dir
from salt://binsvc/blocks/fetch.sls import fetch_source
from salt://binsvc/blocks/venv.sls import python_venv
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
    fixed order: user/ssh, then install_dir (ahead of config - a config entry
    with makedirs would otherwise create the install dir root-owned before the
    service user's ownership is applied), then config, then the svc fetch, then
    venv (after fetch - venv.requirements_files may point at a
    requirements.txt that arrives inside the fetched archive), pre-systemd
    commands, systemd, post-systemd commands, then nginx. Fetch/config/venv
    changes are wired via the `changed` requisite-list contract so systemd
    restarts whenever the binary, config, or requirement set actually
    changed."""

    user_and_ssh(prefix, settings)
    install_dir(prefix, settings)
    changed = list(config_files(prefix, settings) or [])

    svc = settings.get("svc")
    if svc:
        changed = list(fetch_source(prefix, settings) or []) + changed

    changed = list(python_venv(prefix, settings) or []) + changed

    run_commands(prefix, settings, phase="pre", require=changed)

    running = None
    if settings.get("systemd", {}).get("manage", True):
        running = systemd_unit(prefix, settings, watch=changed)

    run_commands(prefix, settings, phase="post", require=running)

    nginx_vhost(prefix, settings)


# --- main loop: merge+format every instance, then gather+dispatch the selected -
#
# Two passes, because cross-instance scrape collection needs every producer
# already formatted. Pass 1 (merge + expand) is purely per-instance and runs for
# ALL instances, so a selected consumer can gather any producer's expanded
# `scrape` jobs - including producers excluded from this apply. Pass 2 gathers
# and dispatches only the `selected` subset. Expansion is uniform: scrape configs
# are expanded by the same two-phase pass as everything else, in the producer's
# own scope - no separate formatting step.

instances = pillar("binsvc:instances", {})

# Operator-defined placeholders shared by every instance, usable as {key} in
# any settings string alongside {name}/{type}/... Literal values, no recursive
# expansion; a key colliding with a reserved placeholder fails loud.
global_vars = pillar("binsvc:globals", {})

# Placeholder names injected into the phase-2 scope (see below). Reserved here so
# a global can't pass the phase-1 collision check and then be silently
# overwritten in the second expand pass.
PHASE2_PLACEHOLDERS = ("install_dir", "exec", "args", "user_name", "user_group", "svc_target", "venv_dir")

# Optional `binsvc:filter` (operator-typed, usually on the CLI) scopes this apply
# to a subset - e.g. pillar='{binsvc: {filter: "name: vm* *gra*"}}'. It gates the
# expensive `latest` resolution (pass 1) and dispatch (pass 2); formatting itself
# runs for every instance so cross-instance scrape gathering stays correct.
selected = select_instances(instances, parse_filter(pillar("binsvc:filter", "")))
if not selected and instances:
    log.warning("binsvc:filter %r matched no instances; nothing to apply",
                pillar("binsvc:filter", ""))

# Pass 1: merge + two-phase expand every instance into a fully formatted dict.
expanded = {}
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

    svc = settings.get("svc") or {}
    # Resolve `latest` only for selected instances - it's the one network step.
    # Unselected producers still format (so consumers can gather their scrape
    # jobs), but their {version}/{tag} stay at the unresolved value.
    if "source" in svc and instance_name in selected:
        settings["svc"] = resolve_latest_version(svc)
        svc = settings["svc"]

    # Phase 1: resolve install_dir/source/exec against grain-derived identity
    # plus the instance's own static keys (name/type/version/tag/...).
    tag = svc.get("tag", svc.get("version", ""))
    base_scope = merge_globals(global_vars,
        extra_reserved=PHASE2_PLACEHOLDERS,
        name=instance_name,
        type=settings.get("type"),
        version=svc.get("version", ""),
        tag=tag,
        tag_vstrip=tag.lstrip("v"),
        osarch=normalize_osarch(grains("osarch") or ""),
        kernel_lower=(grains("kernel") or "").lower(),
        cpuarch=grains("cpuarch") or "",
        grain_id=grains("id") or "",
    )
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
                       user_group=user.get("group", user.get("name", "root")),
                       # Guarded on svc.source so a no-svc (or not-yet-resolved,
                       # e.g. grafana's intentionally-empty source pre-resolve)
                       # instance gets "" instead of fetch_target's ValueError.
                       # {svc_target} is what makes a plaintext-script instance
                       # near zero-config: ExecStart: "{venv_dir}/bin/python {svc_target}".
                       svc_target=fetch_target(svc, settings.get("install_dir", "")) if svc.get("source") else "",
                       # {venv_dir}, never {venv}: expand folds top-level settings
                       # keys into scope, so {venv} would render the config dict's
                       # repr - same reason svc exposes {exec} rather than {svc}.
                       # Already resolved by phase 1 (venv.dir's default
                       # "{install_dir}/venv" self-resolves the same way
                       # install_dir/svc.source do - see WHITEPAPER.md §5).
                       venv_dir=(settings.get("venv") or {}).get("dir", ""))
    settings = expand(settings, extra_scope)

    expanded[instance_name] = settings

# Pass 2: gather cross-instance scrape jobs and dispatch the selected instances.
for instance_name, settings in expanded.items():
    if instance_name not in selected:
        continue

    if "scrape_collect" in settings:
        jobs = collect_scrape_jobs(expanded, instance_name)
        append_at_path(settings, settings["scrape_collect"], jobs, unique_key="job_name")

    dispatch(["binsvc", instance_name], settings)
