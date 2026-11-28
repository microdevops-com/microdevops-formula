"""appsvc lib/core.py

Shared helpers: placeholder expansion (expand/deep_format), the deep merge,
cross-instance scrape collection, the apply filter, user home / known_hosts,
keyed-map key validation, and svc.args merging/joining.

Pure Python, no Salt imports: init.sls and the blocks import it with
`from salt://appsvc/lib/core.py import ...` (one line per import - that is all
the pyobjects renderer parses), and tests load it through tests/conftest.py.
"""

import copy
import fnmatch
import re


# ── substitute ───────────────────────────────────────────────────────────────
# Recursive {placeholder} expansion for nested dict/list/str structures.
# Replaces application/utils.py's format_dict_itself/format_dict_target and
# victoriametrics/_setup.sls's __VM_NAME__ tojson/replace/load_json hack.


class _SafeScope(dict):
    # str.format_map() raises KeyError on a missing name; leave the placeholder
    # untouched instead so partially-known scopes don't blow up and multi-round
    # expansion can fill gaps in later rounds.
    def __missing__(self, key):
        return "{" + key + "}"


def _format(value, scope):
    if isinstance(value, str):
        return value.format_map(scope)
    if isinstance(value, dict):
        return {key: _format(item, scope) for key, item in value.items()}
    if isinstance(value, list):
        return [_format(item, scope) for item in value]
    return value


def deep_format(value, scope):
    """Render every {placeholder} string found anywhere inside `value`
    (recursing into dicts and lists) using `scope`. Returns a new structure;
    `value` is left untouched. Unknown placeholders are left as-is."""
    return _format(value, scope if isinstance(scope, _SafeScope) else _SafeScope(scope))


def expand(mapping, scope=None, rounds=3):
    """Like deep_format, but the mapping's own (progressively expanded) values
    are folded into the scope on each round, so keys can reference each other
    regardless of definition order (e.g. `exec` referencing `install_dir`
    referencing `name`). Returns a new dict; `mapping` is left untouched."""
    result = copy.deepcopy(dict(mapping))
    base = dict(scope or {})

    for _ in range(rounds):
        current = _SafeScope({**base, **result})
        updated = {key: _format(item, current) for key, item in result.items()}
        if updated == result:
            break
        result = updated

    return result


def merge_globals(global_vars, *, extra_reserved=(), **reserved):
    """Overlay operator-supplied `appsvc:globals` onto the reserved expand scope.

    The reserved/derived placeholders are passed directly as keyword arguments
    (`name=..., grain_id=..., ...`); `global_vars` are the operator's literal
    `{key}` values shared by every instance. Raises ValueError if a global key
    shadows a reserved placeholder - that is almost always a typo that would
    otherwise silently break the identity placeholders. `extra_reserved` names
    additional reserved placeholders injected *after* this call (the phase-2
    scope keys), so colliding with them fails loud here instead of being silently
    overwritten in the second expand pass. Returns a new dict; inputs untouched."""
    clash = set(global_vars or {}) & (set(reserved) | set(extra_reserved))
    if clash:
        raise ValueError(
            "appsvc:globals keys shadow reserved placeholders: {}".format(
                ", ".join(sorted(clash))))
    return dict(reserved, **(global_vars or {}))


# ── merge ─────────────────────────────────────────────────────────────────────
# Deep dict merge for the defaults -> preset -> instance layering.
# Generalizes salt.defaults.merge calls scattered through exporter/macro.jinja.


def merge(*layers):
    """Deep-merge dicts left to right; later layers win. Nested dicts are
    merged recursively; any other value (including lists) is replaced
    wholesale by the later layer. Returns a new dict; inputs are untouched."""
    result = {}
    for layer in layers:
        if not layer:
            continue
        for key, value in layer.items():
            existing = result.get(key)
            if isinstance(existing, dict) and isinstance(value, dict):
                result[key] = merge(existing, value)
            else:
                result[key] = copy.deepcopy(value)
    return result


# ── scrape collection ─────────────────────────────────────────────────────────
# Cross-instance scrape-config sharing for vmagent. Producers declare literal
# jobs in `scrape`; consumers opt in with `scrape_collect`.


def collect_scrape_jobs(merged_instances, consumer_name):
    """Gather literal scrape jobs targeting `consumer_name`.

    Producers use `scrape: {vmagent: <scalar|globs>, config: [<job>, ...]}`.
    `vmagent` is required when `scrape` is present; matching nothing is a no-op.
    """
    jobs = []
    for name, settings in merged_instances.items():
        scrape = settings.get("scrape")
        if not scrape:
            continue
        targets = scrape.get("vmagent")
        if targets is None:
            raise ValueError("instance {!r}: 'scrape' requires 'vmagent'".format(name))
        if isinstance(targets, str):
            targets = [targets]
        if any(fnmatch.fnmatch(consumer_name, pat) for pat in targets):
            jobs.extend(scrape.get("config") or [])
    return jobs


def append_at_path(container, path, items, sep=":", unique_key=None):
    """Append `items` to the list at `path`, creating missing dict/list nodes."""
    node = container
    keys = path.split(sep)
    for key in keys[:-1]:
        node = node.setdefault(key, {})
    target = node.setdefault(keys[-1], [])
    target.extend(items)
    if unique_key is not None:
        seen = set()
        for entry in target:
            value = entry.get(unique_key)
            if value in seen:
                raise ValueError("duplicate {}={!r} at {!r}".format(unique_key, value, path))
            seen.add(value)
    return container


# ── filter ────────────────────────────────────────────────────────────────────
# Operator-typed `appsvc:filter` selector to scope `state.apply` to a subset of
# instances. Parsing/matching only - the loop in init.sls still merges ALL
# instances first (so scrape aggregation stays correct), then dispatches just
# the selected ones.

FILTER_KEYS = ("name", "preset")


def parse_filter(spec):
    """Parse a `appsvc:filter` selector string into {key: [globs]}.

    Format: "name: vm* *gra*; preset: exporter*" - semicolon-separated clauses,
    each "<key>: <glob> <glob> ...". Keys must be one of name/preset; an unknown
    key or a clause with no globs raises (a typo fails loud instead of silently
    selecting nothing). Returns {} for an empty/whitespace spec (no filter)."""
    result = {}
    for clause in (spec or "").split(";"):
        clause = clause.strip()
        if not clause:
            continue
        if ":" not in clause:
            raise ValueError(
                "appsvc:filter clause {!r} is not '<key>: <glob>...'".format(clause))
        key, globs = clause.split(":", 1)
        key = key.strip()
        if key not in FILTER_KEYS:
            raise ValueError(
                "appsvc:filter key {!r} unknown; expected one of {}".format(
                    key, ", ".join(FILTER_KEYS)))
        patterns = globs.split()
        if not patterns:
            raise ValueError("appsvc:filter key {!r} has no globs".format(key))
        result.setdefault(key, []).extend(patterns)
    return result


def select_instances(merged_instances, filter_spec):
    """Return the set of instance names to dispatch for a parsed `filter_spec`.

    Empty/None filter -> every instance. Otherwise union semantics: an instance
    is selected if its name matches any `name` glob OR its preset matches any
    `preset` glob. A preset-less instance can only be matched by name."""
    if not filter_spec:
        return set(merged_instances)
    name_globs = filter_spec.get("name", [])
    preset_globs = filter_spec.get("preset", [])
    selected = set()
    for name, settings in merged_instances.items():
        if any(fnmatch.fnmatch(name, g) for g in name_globs):
            selected.add(name)
            continue
        preset = settings.get("preset")
        if preset is not None and any(fnmatch.fnmatch(preset, g) for g in preset_globs):
            selected.add(name)
    return selected


# ── home ──────────────────────────────────────────────────────────────────────
# The {home} placeholder: apps live in the service user's home directory.


def parse_known_host(entry):
    """Parse an `ssh.known_hosts.hosts` entry "host[:port[:enc[:key]]]" into
    (host, port, enc, key). port is an int (default 22), enc defaults to
    ssh-ed25519, key to None (ssh-keyscan fetches it).

    The int matters: Salt's ssh_known_hosts writes "[host]:port" whenever
    port != 22, so a string "22" produced an entry OpenSSH never matches for
    the default port ("Host key verification failed")."""
    parts = str(entry).split(":")
    if len(parts) > 4 or not parts[0]:
        raise ValueError("ssh.known_hosts entry {!r} is not host[:port[:enc[:key]]]".format(entry))
    host = parts[0]
    try:
        port = int(parts[1]) if len(parts) > 1 and parts[1] else 22
    except ValueError:
        raise ValueError("ssh.known_hosts entry {!r}: port {!r} is not a number".format(entry, parts[1]))
    enc = parts[2] if len(parts) > 2 and parts[2] else "ssh-ed25519"
    key = parts[3] if len(parts) > 3 and parts[3] else None
    return host, port, enc, key


def user_home(user):
    """Home directory of the instance user: `user.home` if set, else /root for
    root (or an empty `user`), else /home/<name>."""
    user = user or {}
    if user.get("home"):
        return user["home"]
    name = user.get("name") or "root"
    return "/root" if name == "root" else "/home/{}".format(name)


# ── keyed-map keys ────────────────────────────────────────────────────────────
# The key of sources/dirs/cron entries becomes part of a Salt state ID (and, for
# cron, of the crontab identifier), so restrict its charset.

_KEY_RE = re.compile(r"^[A-Za-z0-9_.-]+$")


def check_map_key(what, key):
    """Raise ValueError unless `key` is a non-empty [A-Za-z0-9_.-]+ string."""
    if not isinstance(key, str) or not _KEY_RE.match(key):
        raise ValueError("{}: invalid key {!r} - keys become part of a state ID, "
                         "allowed characters are [A-Za-z0-9_.-]".format(what, key))
    return key


def _check_unknown_keys(what, key, item, allowed):
    unknown = sorted(str(k) for k in item if k not in allowed)
    if unknown:
        raise ValueError("{}:{}: unknown key(s) {} - allowed: {}".format(
            what, key, ", ".join(unknown), ", ".join(sorted(allowed))))


# ── svc.args ──────────────────────────────────────────────────────────────────
# Structured `svc.args`: merged by flag name across layers, joined into {args}.


def merge_args(*layers):
    """Merge structured `args` layers by flag name.

    Layers may be a `{flag: value}` mapping, an ordered list of single-key
    mappings and/or raw string tokens, or a top-level raw string. A top-level
    string and repeated flags fall back to returning the last non-empty layer
    unchanged because there is no reliable key-level merge for those shapes.
    """
    non_empty = [layer for layer in layers if layer]
    if any(isinstance(layer, str) for layer in non_empty):
        return non_empty[-1] if non_empty else []

    def entries_of(layer):
        if not layer:
            return []
        if isinstance(layer, dict):
            return [("key", key, value) for key, value in layer.items()]
        entries = []
        for entry in layer:
            if isinstance(entry, str):
                entries.append(("raw", entry, None))
            else:
                entries.extend(("key", key, value) for key, value in entry.items())
        return entries

    layer_entries = [entries_of(layer) for layer in non_empty]

    for entries in layer_entries:
        keys = [key for kind, key, _ in entries if kind == "key"]
        if len(set(keys)) != len(keys):
            return non_empty[-1] if non_empty else []

    order = []
    values = {}
    for entries in layer_entries:
        for kind, key, value in entries:
            if kind == "raw":
                order.append(("raw", key))
                continue
            if key not in values:
                order.append(("key", key))
            values[key] = value
    return [{value: values[value]} if kind == "key" else value
            for kind, value in order]


def join_args(args, prefix="-"):
    """Turn `{flag: value}` (or an ordered list of single-key mappings/raw
    string tokens) into a command-line string.

    Top-level raw string args are returned unchanged. Mapping entries render as
    `{prefix}{flag}={value}`, or as a bare `{prefix}{flag}` when the value is
    null (YAML `- foobar:`); raw string entries render as-is. `prefix` defaults
    to the short flag form.
    """
    def flag(key, value):
        if value is None:
            return "{}{}".format(prefix, key)
        return "{}{}={}".format(prefix, key, value)

    if isinstance(args, str):
        return args
    if isinstance(args, dict):
        items = [flag(key, value) for key, value in args.items()]
    else:
        items = []
        for entry in args:
            if isinstance(entry, str):
                items.append(entry)
            else:
                items.extend(flag(key, value) for key, value in entry.items())
    return " ".join(items)
