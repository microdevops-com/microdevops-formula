"""appsvc lib/app.py

Application blocks: commands (phases, onchanges), git sources, dirs, cron
entries and config-file rendering.

Pure Python, no Salt imports: init.sls and the blocks import it with
`from salt://appsvc/lib/app.py import ...` (one line per import - that is all
the pyobjects renderer parses), and tests load it through tests/conftest.py.
"""

import configparser
import io
import json

import yaml

from salt://appsvc/lib/core.py import _check_unknown_keys, check_map_key


# ── commands ──────────────────────────────────────────────────────────────────
# Pure selection logic for the commands block. The Salt block only emits states.


def select_commands(commands, phase, settings):
    """Pick command entries for `phase`, preserving declaration order.

    Skips malformed entries, entries for another phase (default: post), and
    entries gated by `when_set` when the named settings key is absent/falsy.
    """
    selected = []
    for name, item in (commands or {}).items():
        if not isinstance(item, dict) or "cmd" not in item:
            continue
        if item.get("phase", "post") != phase:
            continue
        when = item.get("when_set")
        if when is not None and not settings.get(when):
            continue
        selected.append((name, item))
    return selected


# ── sources ───────────────────────────────────────────────────────────────────
# Git checkouts (the `sources` block). Pure derivation of git.latest / git.cloned
# kwargs; the block only emits the state.

SOURCE_COMMON_KEYS = ("git", "target", "once", "branch", "identity")
SOURCE_LATEST_ONLY_KEYS = ("rev", "depth", "submodules", "force_reset",
                           "force_checkout", "force_clone", "force_fetch")
SOURCE_KEYS = SOURCE_COMMON_KEYS + SOURCE_LATEST_ONLY_KEYS


def git_source_state(key, source, user_name):
    """Derive `(function_name, kwargs)` for one `sources` entry: function_name is
    "latest" or "cloned" (`once: true`), kwargs are ready for Git.<function_name>.

    `force_reset` is deliberately NOT defaulted (app.* defaults it to true,
    which silently discards local changes on the server): unset, git.latest
    fails loud on a dirty tree. Raises ValueError (naming the key) on a bad
    map key, missing/empty `git`, missing or non-absolute `target`, unknown
    keys, or `once: true` combined with a git.latest-only key."""
    check_map_key("sources", key)
    if not isinstance(source, dict):
        raise ValueError("sources:{}: must be a mapping, got {!r}".format(key, source))
    _check_unknown_keys("sources", key, source, SOURCE_KEYS)

    if not source.get("git"):
        raise ValueError("sources:{}: `git` (repository URL) is required".format(key))
    target = source.get("target")
    if not target or not isinstance(target, str) or not target.startswith("/"):
        raise ValueError("sources:{}: `target` must be an absolute path after expansion "
                         "(use {{home}}, not ~), got {!r}".format(key, target))

    once = bool(source.get("once", False))
    if once:
        clash = [k for k in SOURCE_LATEST_ONLY_KEYS if k in source]
        if clash:
            raise ValueError("sources:{}: `once: true` uses git.cloned, which does not "
                             "support {} (git.latest-only)".format(key, ", ".join(clash)))

    kwargs = {"name": source["git"], "target": target}
    if user_name and user_name != "root":
        kwargs["user"] = user_name
    for opt in ("branch", "identity") + SOURCE_LATEST_ONLY_KEYS:
        if opt in source:
            kwargs[opt] = source[opt]
    return ("cloned" if once else "latest"), kwargs


def _norm_path(path):
    """Strip trailing slashes (keeps a bare "/" as "/")."""
    return path.rstrip("/") or "/"


def sources_containing(path, sources):
    """Sorted keys of the `sources` entries whose `target` contains `path`:
    equal to it, or under it with a `/` boundary (/a/b is not inside /a/bc).
    Trailing slashes are ignored. `sources` is the expanded settings["sources"]
    map (may be empty/None); entries without a string `target` are skipped
    (git_source_state fails loud on those)."""
    if not sources or not isinstance(path, str):
        return []
    path = _norm_path(path)
    found = []
    for key, source in sources.items():
        target = source.get("target") if isinstance(source, dict) else None
        if not isinstance(target, str) or not target:
            continue
        target = _norm_path(target)
        if path == target or path.startswith(target.rstrip("/") + "/"):
            found.append(key)
    return sorted(found)


# ── commands: onchanges ───────────────────────────────────────────────────────

ONCHANGES_BLOCKS = ("sources",)


def parse_onchanges(spec):
    """Validate a command's `onchanges` list and return [(block, key_or_None)].
    Entries are "<block>" (any entry of that block changed) or "<block>:<key>".
    Only `sources` is a valid block in this step. Raises ValueError on a
    non-list, an empty list (the gate could never fire), a non-string entry,
    an unknown block, or an empty key."""
    if not isinstance(spec, list):
        raise ValueError("commands onchanges must be a list like [sources:backend], "
                         "got {!r}".format(spec))
    if not spec:
        raise ValueError("commands onchanges is empty - the command would never run")
    parsed = []
    for entry in spec:
        if not isinstance(entry, str):
            raise ValueError("commands onchanges entry {!r} must be a string".format(entry))
        block, sep, key = entry.partition(":")
        if block not in ONCHANGES_BLOCKS:
            raise ValueError("commands onchanges {!r}: unknown block {!r}, valid: {}".format(
                entry, block, ", ".join(ONCHANGES_BLOCKS)))
        if sep and not key:
            raise ValueError("commands onchanges {!r}: empty key after ':'".format(entry))
        parsed.append((block, key if sep else None))
    return parsed


def resolve_onchanges(cmd_name, spec, refs):
    """Resolve a command's `onchanges` spec against `refs` ({block: {key: ref}})
    to a flat, de-duplicated list of refs. Raises ValueError for an unknown
    key or when nothing resolves (the command could never run)."""
    refs = refs or {}
    resolved = []
    for block, key in parse_onchanges(spec):
        available = refs.get(block) or {}
        if key is None:
            picked = list(available.values())
        elif key in available:
            picked = [available[key]]
        else:
            raise ValueError("commands:{}: onchanges {}:{} - no such {} entry (declared: {})".format(
                cmd_name, block, key, block, ", ".join(sorted(available)) or "none"))
        for ref in picked:
            if ref not in resolved:
                resolved.append(ref)
    if not resolved:
        raise ValueError("commands:{}: onchanges {!r} resolved to nothing (no {} declared) - "
                         "the command could never run".format(cmd_name, spec, "/".join(ONCHANGES_BLOCKS)))
    return resolved


# ── dirs ──────────────────────────────────────────────────────────────────────

DIR_KEYS = ("name", "user", "group", "mode", "makedirs", "recurse")


def normalize_dirs(dirs, user_name, user_group):
    """Turn the `dirs` keyed map into an ordered list of `(key, kwargs)` for
    File.directory. A string value is shorthand for `{name: <string>}`.
    Defaults: user/group = the instance user/group, mode "755", makedirs true;
    `recurse: true` -> recurse=["user", "group"] (never mode). `mode` must be a
    string (an unquoted YAML 750 / 0750 is an int and would be silently wrong).
    Raises ValueError on bad keys, unknown keys, or a missing/relative name."""
    if not dirs:
        return []
    if not isinstance(dirs, dict):
        raise ValueError("dirs must be a keyed map, got {!r}".format(dirs))
    result = []
    for key, item in dirs.items():
        check_map_key("dirs", key)
        if isinstance(item, str):
            item = {"name": item}
        if not isinstance(item, dict):
            raise ValueError("dirs:{}: must be a path string or a mapping, got {!r}".format(key, item))
        _check_unknown_keys("dirs", key, item, DIR_KEYS)
        name = item.get("name")
        if not isinstance(name, str) or not name.startswith("/"):
            raise ValueError("dirs:{}: `name` must be an absolute path after expansion "
                             "(use {{home}}, not ~), got {!r}".format(key, name))
        mode = item.get("mode", "755")
        if not isinstance(mode, str):
            raise ValueError("dirs:{}: `mode` must be a quoted string like \"750\", "
                             "got {!r}".format(key, mode))
        kwargs = {
            "name": name,
            "user": item.get("user", user_name),
            "group": item.get("group", user_group),
            "mode": mode,
            "makedirs": bool(item.get("makedirs", True)),
        }
        if item.get("recurse", False):
            kwargs["recurse"] = ["user", "group"]
        result.append((key, kwargs))
    return result


def check_dirs_outside_sources(dirs_normalized, sources):
    """Raise ValueError when a normalized `dirs` entry (the `(key, kwargs)` list
    from normalize_dirs) lies inside a `sources` target. dirs run before
    sources, so the directory would make the checkout's target non-empty and
    non-repo and every git.cloned/git.latest would refuse it."""
    for key, kwargs in dirs_normalized:
        inside = sources_containing(kwargs["name"], sources)
        if inside:
            raise ValueError(
                "dirs:{}: {!r} is inside the checkout of sources:{} - dirs run before "
                "sources, so it would make the clone target non-empty and block the "
                "clone. Use a `commands` entry with `onchanges: [sources:{}]` to create "
                "it after the checkout, or put the directory outside the checkout"
                .format(key, kwargs["name"], inside[0], inside[0]))


# ── cron ──────────────────────────────────────────────────────────────────────

CRON_KEYS = ("schedule", "cmd", "user", "comment", "disabled", "absent")
CRON_SPECIALS = ("@reboot", "@yearly", "@annually", "@monthly", "@weekly",
                 "@daily", "@midnight", "@hourly")
CRON_FIELDS = ("minute", "hour", "daymonth", "month", "dayweek")


def cron_identifier(instance_name, key):
    """Salt cron `identifier`, unique across instances sharing a crontab."""
    return "appsvc_{}_{}".format(instance_name, key)


def cron_schedule_kwargs(schedule):
    """`{"special": "@daily"}` for one @-token, or minute/hour/daymonth/month/
    dayweek for five whitespace-separated fields. Raises ValueError otherwise
    (including a single non-@ token or an unknown @special)."""
    parts = schedule.split() if isinstance(schedule, str) else []
    if len(parts) == 1 and parts[0].startswith("@"):
        if parts[0] not in CRON_SPECIALS:
            raise ValueError("cron schedule {!r}: unknown special, valid: {}".format(
                schedule, ", ".join(CRON_SPECIALS)))
        return {"special": parts[0]}
    if len(parts) == 5:
        return dict(zip(CRON_FIELDS, parts))
    raise ValueError("cron schedule {!r}: expected five fields or one @special "
                     "({})".format(schedule, ", ".join(CRON_SPECIALS)))


def normalize_cron(cron, instance_name, default_user):
    """Turn the `cron` keyed map into an ordered list of
    `(key, function_name, kwargs)` for Cron.present / Cron.absent.

    `cmd` and `schedule` are required unless `absent: true`, which only needs
    the user + identifier (Salt matches on identifier; `name` is passed only if
    `cmd` was given). `disabled: true` -> commented=True. Raises ValueError on a
    bad key, unknown keys, or missing cmd/schedule."""
    if not cron:
        return []
    if not isinstance(cron, dict):
        raise ValueError("cron must be a keyed map, got {!r}".format(cron))
    result = []
    for key, item in cron.items():
        check_map_key("cron", key)
        if not isinstance(item, dict):
            raise ValueError("cron:{}: must be a mapping, got {!r}".format(key, item))
        _check_unknown_keys("cron", key, item, CRON_KEYS)
        kwargs = {"user": item.get("user", default_user),
                  "identifier": cron_identifier(instance_name, key)}
        if item.get("cmd"):
            kwargs["name"] = item["cmd"]
        if item.get("absent", False):
            result.append((key, "absent", kwargs))
            continue
        for required in ("cmd", "schedule"):
            if not item.get(required):
                raise ValueError("cron:{}: `{}` is required (unless `absent: true`)".format(key, required))
        kwargs.update(cron_schedule_kwargs(item["schedule"]))
        if item.get("comment"):
            kwargs["comment"] = item["comment"]
        if item.get("disabled", False):
            kwargs["commented"] = True
        result.append((key, "present", kwargs))
    return result


# ── config ────────────────────────────────────────────────────────────────────
# Render a config-file body from structured `contents` in a chosen format.
# Kept in lib/ so format behavior is unit-tested without a minion.


def render_config(contents, fmt="yaml"):
    """Render `contents` to a config-file body string in `fmt` (yaml|ini|json).

    Raises ValueError on an unsupported format. Placeholders in `contents` are
    already expanded by init.sls before this runs.
    """
    if fmt in ("yaml", "yml"):
        return yaml.safe_dump(contents, default_flow_style=False)
    if fmt == "json":
        return json.dumps(contents, indent=2) + "\n"
    if fmt == "ini":
        return _render_ini(contents)
    raise ValueError("unsupported config format: {!r}".format(fmt))


def _render_ini(contents):
    """Render one-level INI sections: {section: {key: value}}.

    Raises on non-mapping input or deeper nesting so bad pillar fails clearly
    instead of flattening into a surprising file.
    """
    if not isinstance(contents, dict):
        raise ValueError("ini config must be a mapping of sections, got {}".format(type(contents).__name__))

    # interpolation=None: a literal % in a value (e.g. a time format like %Y)
    # must not be parsed as interpolation syntax - configparser otherwise raises.
    # optionxform=str: preserve key case (configparser lowercases keys by default).
    parser = configparser.ConfigParser(interpolation=None)
    parser.optionxform = str
    for section, options in contents.items():
        if not isinstance(options, dict):
            raise ValueError("ini config: section {!r} must map to a dict".format(section))
        parser[section] = {}
        for key, value in options.items():
            if isinstance(value, (dict, list)):
                raise ValueError("ini supports section/key/value only; {}.{} is nested".format(section, key))
            parser[section][key] = str(value)

    buf = io.StringIO()
    parser.write(buf)
    return buf.getvalue()
