"""appsvc lib/systemd.py

Systemd units (`systemd.units` planning, unit-name checks) and INI rendering.

Pure Python, no Salt imports: init.sls and the blocks import it with
`from salt://appsvc/lib/systemd.py import ...` (one line per import - that is all
the pyobjects renderer parses), and tests load it through tests/conftest.py.
"""

import fnmatch
import re

from salt://appsvc/lib/core.py import _check_unknown_keys, check_map_key, deep_format, merge


# ── systemd units ────────────────────────────────────────────────────────────
# `systemd.units` is a keyed map: the key is the unit's identity for merging
# (a preset defines `main`, an instance overrides `main.Service.ExecStart`) and
# the `{unit}` placeholder; `name` is the systemd unit name, defaulting to
# systemd.defaults.name ("appsvc_{name}_{unit}"). Bundled presets pin
# `name: "appsvc_{name}"` so their units keep the pre-0.2 name.

SYSTEMD_KEYS = ("manage", "defaults", "units")
SYSTEMD_SECTIONS = ("Unit", "Service", "Install")
SYSTEMD_DEFAULTS_KEYS = ("name",) + SYSTEMD_SECTIONS
SYSTEMD_UNIT_KEYS = ("name", "delete") + SYSTEMD_SECTIONS
SYSTEMD_UNIT_DIR = "/etc/systemd/system"
_UNIT_NAME_RE = re.compile(r"^[A-Za-z0-9:_.-]+$")
_OTHER_UNIT_SUFFIXES = (".socket", ".timer", ".target", ".path", ".mount", ".automount",
                        ".swap", ".slice", ".scope", ".device")
# A file in /etc/systemd/system overrides the packaged unit of the same name in
# /lib/systemd/system, so these would silently replace (or, with delete: true,
# stop) a distro service. Not exhaustive - the obvious ones on our hosts.
SYSTEMD_RESERVED_NAMES = ("nginx", "apache2", "php*-fpm", "redis", "redis-server", "redis-sentinel",
                          "mysql", "mysqld", "mariadb", "postgresql", "mongod", "rabbitmq-server",
                          "docker", "containerd", "ssh", "sshd", "cron", "supervisor", "ufw",
                          "networking", "dbus", "salt-minion", "salt-master", "systemd-*")


def _unit_name(raw, where):
    """Validated unit name without the `.service` suffix."""
    if not isinstance(raw, str) or not raw:
        raise ValueError("{}: `name` must be a non-empty string, got {!r}".format(where, raw))
    name = raw[:-len(".service")] if raw.endswith(".service") else raw
    if name.endswith(_OTHER_UNIT_SUFFIXES):
        raise ValueError("{}: `name` {!r} - only .service units are supported".format(where, raw))
    if not _UNIT_NAME_RE.match(name):
        raise ValueError("{}: invalid unit `name` {!r} - allowed characters are [A-Za-z0-9:_.-] "
                         "(an unresolved placeholder left braces in it?)".format(where, raw))
    if any(fnmatch.fnmatchcase(name, pattern) for pattern in SYSTEMD_RESERVED_NAMES):
        raise ValueError("{}: unit `name` {!r} is a distro service name - a file in {} would "
                         "override the packaged unit; pick another name".format(where, name, SYSTEMD_UNIT_DIR))
    return name


def systemd_plan(systemd, instance_name):
    """Validated units of one instance, in pillar order: [{key, name (no
    .service suffix), path, delete, sections}]. [] when systemd.manage is false
    or there are no units. Each unit is merge(systemd.defaults, unit); `{unit}`
    (the key) is filled in `name`, then `{unit}` and `{unit_name}` in the
    sections. A unit that isn't `delete: true` needs Service.ExecStart.

    Old-shape keys (systemd.Unit/Service/Install/unit) are reported by
    compat.py before this runs; here they are just unknown keys."""
    systemd = systemd or {}
    if not isinstance(systemd, dict):
        raise ValueError("systemd must be a mapping, got {!r}".format(systemd))
    _check_unknown_keys("instance {}".format(instance_name), "systemd", systemd, SYSTEMD_KEYS)
    if not systemd.get("manage", True):
        return []
    defaults = systemd.get("defaults") or {}
    if not isinstance(defaults, dict):
        raise ValueError("systemd.defaults must be a mapping, got {!r}".format(defaults))
    _check_unknown_keys("systemd", "defaults", defaults, SYSTEMD_DEFAULTS_KEYS)
    units = systemd.get("units") or {}
    if not isinstance(units, dict):
        raise ValueError("systemd.units must be a keyed map, got {!r}".format(units))

    result, seen = [], {}
    for key, unit in units.items():
        check_map_key("systemd.units", key)
        where = "instance {}: systemd.units.{}".format(instance_name, key)
        unit = unit or {}
        if not isinstance(unit, dict):
            raise ValueError("{}: must be a mapping, got {!r}".format(where, unit))
        _check_unknown_keys("systemd.units", key, unit, SYSTEMD_UNIT_KEYS)
        delete = unit.get("delete", False)
        if not isinstance(delete, bool):
            raise ValueError("{}: `delete` must be true or false, got {!r}".format(where, delete))
        merged = merge(defaults, unit)
        name = _unit_name(deep_format(merged.get("name"), {"unit": key}), where)
        if name in seen:
            raise ValueError("instance {}: systemd.units.{} and systemd.units.{} both name unit {}.service"
                             .format(instance_name, seen[name], key, name))
        seen[name] = key
        sections = {}
        for section in SYSTEMD_SECTIONS:
            value = merged.get(section)
            if value is None or value == {}:
                continue
            if not isinstance(value, dict):
                raise ValueError("{}: {} must be a mapping, got {!r}".format(where, section, value))
            sections[section] = deep_format(value, {"unit": key, "unit_name": name})
        if not delete:
            exec_start = (sections.get("Service") or {}).get("ExecStart")
            if isinstance(exec_start, (list, tuple)):
                exec_start = " ".join(str(e) for e in exec_start)
            if not exec_start or not str(exec_start).strip():
                raise ValueError("{}: Service.ExecStart is missing/empty - set it, mark the unit "
                                 "`delete: true`, or set systemd.manage: false".format(where))
        result.append({"key": key, "name": name, "delete": delete, "sections": sections,
                       "path": "{}/{}.service".format(SYSTEMD_UNIT_DIR, name)})
    return result


def check_unit_names(plans):
    """Fail when two instances manage (define or delete) the same unit name.
    `plans` is {instance: systemd_plan(...)}. Unit names are host-global while
    state IDs are per instance, so Salt itself would not notice two instances
    fighting over one unit file."""
    owners = {}
    for instance, units in plans.items():
        for unit in units:
            owners.setdefault(unit["name"], []).append("{}:{}".format(instance, unit["key"]))
    clashes = {name: who for name, who in owners.items() if len(who) > 1}
    if clashes:
        raise ValueError("systemd unit names used by more than one instance: " + "; ".join(
            "{}.service <- {}".format(name, ", ".join(who)) for name, who in sorted(clashes.items())))


# ── unit rendering ────────────────────────────────────────────────────────────
# Unit file rendering and args-list helpers.


def render_unit(sections):
    """Render an INI-style systemd unit from an ordered {section: {key: value}}
    mapping. A list value produces one `key=item` line per item (repeatable
    directives, e.g. multiple `After=`)."""
    lines = []
    for section, options in sections.items():
        lines.append("[{}]".format(section))
        for key, value in options.items():
            for item in (value if isinstance(value, list) else [value]):
                lines.append("{}={}".format(key, item))
        lines.append("")
    return "\n".join(lines).rstrip("\n") + "\n"
