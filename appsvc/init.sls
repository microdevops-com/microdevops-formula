#!pyobjects
# vim: set ft=python:

# appsvc: run N instances of a service or application -
# prebuilt binaries (VictoriaMetrics, Grafana, exporters, ...), Python daemons,
# and (in progress) multi-runtime web apps - under systemd, each independently configured from one merged
# defaults -> preset -> instance settings dict. See readme.md for the full
# pillar shape and WHITEPAPER.md for the design rationale.

import logging
import yaml

from salt://appsvc/compat.py import check_compat
from salt://appsvc/lib/core.py import INSTALL_DIR_PLACEHOLDER, append_at_path, check_dir_isolation, check_install_dir_set, check_no_install_dir_used, collect_scrape_jobs, expand, join_args, lift_dir_specs, merge, merge_args, merge_globals, parse_filter, select_instances, selected_blocks, split_dir_perms, user_home
from salt://appsvc/lib/release.py import fetch_target, normalize_osarch, resolve_latest
from salt://appsvc/lib/runtimes.py import runtime_paths
from salt://appsvc/lib/systemd.py import check_unit_names, systemd_plan

from salt://appsvc/dispatch.sls import dispatch
from salt://appsvc/utils.sls import get_salt_file

log = logging.getLogger(__name__)


# --- defaults & presets -------------------------------------------------------
#
# get_salt_file (appsvc/utils.sls) uses salt.fileclient directly and works
# under salt-ssh. __salt__["cp.get_file_str"] does not work there.

DEFAULTS = yaml.safe_load(get_salt_file("salt://appsvc/defaults.yaml") or "") or {}

_preset_cache = {}


def cfg(key, default=None):
    """pillar("appsvc:<key>") with a default."""
    return pillar("appsvc:" + key, default)


def load_preset(name):
    """Lazily load & cache a bundled preset (salt://appsvc/presets/{name}.yaml),
    deep-merged with any pillar override at appsvc:presets:{name}. Presets ship
    with the formula so instances only need to override what differs, instead
    of copying whole app configs into pillar. A preset name with no matching
    bundled file is treated as empty - only the pillar override applies."""
    if name not in _preset_cache:
        _content = get_salt_file("salt://appsvc/presets/{}.yaml".format(name), missing_ok=True)
        bundled = yaml.safe_load(_content or "") or {}
        override = cfg("presets:{}".format(name), {})
        _preset_cache[name] = merge(lift_dir_specs(bundled), lift_dir_specs(override or {}))
    return _preset_cache[name]


# --- "latest" version resolution ---------------------------------------------

def resolve_latest_version(svc_settings):
    """Delegate version/source resolution to lib/release.py's named resolver registry.
    Passes the shared resolve-cache config (DEFAULTS, not per-instance: the cache
    is keyed by API URL and shared across instances/minions on the render host)."""
    context = {
        "osarch": normalize_osarch(grains("osarch") or ""),
        "cache_dir": DEFAULTS.get("cache_dir"),
        "resolve_cache_ttl": DEFAULTS.get("resolve_cache_ttl", 0),
        "github_token": cfg("github_token", None),
    }
    return resolve_latest(svc_settings, svc_settings.get("version_resolver", "github"), context)


# --- main loop: merge+format every instance, then gather+dispatch the selected -
#
# Two passes, because cross-instance scrape collection needs every producer
# already formatted. Pass 1 (merge + expand) is purely per-instance and runs for
# ALL instances, so a selected consumer can gather any producer's expanded
# `scrape` jobs - including producers excluded from this apply. Pass 2 gathers
# and dispatches only the `selected` subset. Expansion is uniform: scrape configs
# are expanded by the same two-phase pass as everything else, in the producer's
# own scope - no separate formatting step.

instances = cfg("instances", {})

# Old pillar shapes (formats a later appsvc version changed) fail first, all at
# once, each pointing at its CHANGELOG.md entry - see compat.py.
check_compat(instances, cfg("presets", {}))

# Operator-defined placeholders shared by every instance, usable as {key} in
# any settings string alongside {name}/{type}/... Literal values, no recursive
# expansion; a key colliding with a reserved placeholder fails loud.
global_vars = cfg("globals", {})

# Placeholder names injected into the phase-2 scope (see below). Reserved here so
# a global can't pass the phase-1 collision check and then be silently
# overwritten in the second expand pass.
PHASE2_PLACEHOLDERS = ("install_dir", "exec", "args", "user_name", "user_group", "svc_target", "venv_dir", "home",
                      "nvm_dir", "pyenv_root", "tools_dir", "env_sh",
                      # filled per systemd unit by lib/systemd.py:systemd_plan
                      "unit", "unit_name",
                      # filled per vhost / pool by lib/web.py
                      "vhost", "vhost_name", "pool", "pool_name", "php_version")

# Optional `appsvc:filter` (operator-typed, usually on the CLI) scopes this apply
# to a subset - e.g. pillar='{appsvc: {filter: "name: vm* *gra*; block: cron"}}'.
# name/preset gate the expensive `latest` resolution (pass 1) and dispatch
# (pass 2); `block` limits which blocks dispatch emits for the selected
# instances. Formatting itself runs for every instance so cross-instance scrape
# gathering and unit-name checks stay correct.
filter_spec = parse_filter(cfg("filter", ""))
selected = select_instances(instances, filter_spec)
blocks = selected_blocks(filter_spec)
if not selected and instances:
    log.warning("appsvc:filter %r matched no instances; nothing to apply",
                cfg("filter", ""))

# Pass 1: merge + two-phase expand every instance into a fully formatted dict.
expanded = {}
for instance_name, instance in instances.items():
    preset_name = instance.get("preset")
    preset = load_preset(preset_name) if preset_name else {}

    # install_dir / user.home may be a path or {name, group, mode}: lifted to
    # mappings so the layers merge key by key, then back to path strings
    # before expand (see lib/core.py:lift_dir_specs / split_dir_perms).
    settings = merge(*(lift_dir_specs(layer) for layer in (DEFAULTS, preset, instance)))
    settings["name"] = instance_name
    # No default install_dir: the preset or the instance sets it (null = none).
    check_install_dir_set(settings, instance_name)
    settings = split_dir_perms(settings)
    # install_dir: null - dropped from settings and kept as a literal
    # {install_dir} in the phase-2 scope (None would render "None"), so any
    # applied setting still using it is found after expand.
    no_install_dir = settings.get("install_dir") is None
    if no_install_dir:
        settings.pop("install_dir")
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
    user_name = user.get("name", "root")
    home = user_home(user)
    # Runtime paths (nvm_dir/pyenv_root/tools_dir/env_sh): per-user layout for a
    # non-root user, global for root, explicit nvm.dir/pyenv.root/shell_env.path win.
    runtime = runtime_paths(user_name, home, instance_name, settings.get("nvm"),
                            settings.get("pyenv"), settings.get("shell_env"),
                            scope={"home": home, "user_name": user_name,
                                   "install_dir": settings.get("install_dir", INSTALL_DIR_PLACEHOLDER)})
    extra_scope = dict(base_scope,
                       nvm_dir=runtime["nvm_dir"],
                       pyenv_root=runtime["pyenv_root"],
                       tools_dir=runtime["tools_dir"],
                       env_sh=runtime["env_sh"],
                       install_dir=settings.get("install_dir", INSTALL_DIR_PLACEHOLDER),
                       exec=svc.get("exec", ""),
                       args=join_args(svc.get("args", []), svc.get("args_prefix", "-") or "-"),
                       user_name=user.get("name", "root"),
                       user_group=user.get("group", user.get("name", "root")),
                       home=user_home(user),
                       # Guarded on svc.source so a no-svc (or not-yet-resolved,
                       # e.g. grafana's intentionally-empty source pre-resolve)
                       # instance gets "" instead of fetch_target's ValueError.
                       # {svc_target} is what makes a plaintext-script instance
                       # near zero-config: ExecStart: "{venv_dir}/bin/python {svc_target}".
                       svc_target=fetch_target(svc, settings.get("install_dir", INSTALL_DIR_PLACEHOLDER)) if svc.get("source") else "",
                       # {venv_dir}, never {venv}: expand folds top-level settings
                       # keys into scope, so {venv} would render the config dict's
                       # repr - same reason svc exposes {exec} rather than {svc}.
                       # Already resolved by phase 1 (venv.dir's default
                       # "{install_dir}/venv" self-resolves the same way
                       # install_dir/svc.source do - see WHITEPAPER.md §5).
                       venv_dir=(settings.get("venv") or {}).get("dir", ""))
    settings = expand(settings, extra_scope)

    if no_install_dir:
        check_no_install_dir_used(settings, instance_name,
                                  systemd_plan(settings.get("systemd"), instance_name))
        settings["install_dir"] = None

    expanded[instance_name] = settings

# Unit names are host-global: two instances must not manage the same unit.
# Checked across ALL instances, not just the selected ones.
check_unit_names({instance_name: systemd_plan(settings.get("systemd"), instance_name)
                  for instance_name, settings in expanded.items()})
# A user in the group that guards another instance's 750 home/install_dir
# (typically www-data) could read it.
check_dir_isolation(expanded)

# Pass 2: gather cross-instance scrape jobs and dispatch the selected instances.
for instance_name, settings in expanded.items():
    if instance_name not in selected:
        continue

    if "scrape_collect" in settings:
        jobs = collect_scrape_jobs(expanded, instance_name)
        append_at_path(settings, settings["scrape_collect"], jobs, unique_key="job_name")

    dispatch(["appsvc", instance_name], settings, blocks)
