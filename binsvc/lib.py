"""binsvc lib — all pure Python helpers for the binsvc formula.

Imported via `from salt://binsvc/lib.py import ...` (no sys.path or hardcoded
FORMULA_DIR needed). `init.sls` imports the helpers it uses directly, and block
files that need helpers carry their own top-level `from salt://...` imports so
pyobjects populates each block's frozen globals during that block's import.
Directly importable by pytest for unit tests.

Sections: substitute · merge · scrape · fetch · release · commands · config · nginx · systemd
"""

import configparser
import copy
import fcntl
import fnmatch
import hashlib
import io
import json
import logging
import os
import re
import tempfile
import time

import requests
import yaml

log = logging.getLogger(__name__)


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
    """Overlay operator-supplied `binsvc:globals` onto the reserved expand scope.

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
            "binsvc:globals keys shadow reserved placeholders: {}".format(
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
# Operator-typed `binsvc:filter` selector to scope `state.apply` to a subset of
# instances. Parsing/matching only - the loop in init.sls still merges ALL
# instances first (so scrape aggregation stays correct), then dispatches just
# the selected ones.

FILTER_KEYS = ("name", "preset")


def parse_filter(spec):
    """Parse a `binsvc:filter` selector string into {key: [globs]}.

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
                "binsvc:filter clause {!r} is not '<key>: <glob>...'".format(clause))
        key, globs = clause.split(":", 1)
        key = key.strip()
        if key not in FILTER_KEYS:
            raise ValueError(
                "binsvc:filter key {!r} unknown; expected one of {}".format(
                    key, ", ".join(FILTER_KEYS)))
        patterns = globs.split()
        if not patterns:
            raise ValueError("binsvc:filter key {!r} has no globs".format(key))
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


# ── fetch ─────────────────────────────────────────────────────────────────────
# Local cache paths, arch-name normalisation, and archive extraction commands.


_OSARCH_ALIASES = {"x86_64": "amd64", "aarch64": "arm64"}


def normalize_osarch(osarch):
    """Map uname-style arch names to GOARCH-style names used in most release
    archive filenames (VictoriaMetrics, node_exporter, ...)."""
    return _OSARCH_ALIASES.get(osarch, osarch)


def archive_path(cache_dir, kind, source):
    """Local cache path for a downloaded file, named after the URL's basename."""
    return "{}/{}/{}".format(cache_dir.rstrip("/"), kind, source.rsplit("/", 1)[-1])


def tar_extract_command(archive, install_dir, args="", unpack=""):
    """`tar` invocation extracting `archive` into `install_dir`."""
    parts = ["tar"]
    if args:
        parts.append(args)
    parts += ["--no-same-owner", "--directory", install_dir, "--extract", "--file", archive]
    if unpack:
        parts.append(unpack)
    return " ".join(parts)


# ── release ───────────────────────────────────────────────────────────────────
# Version/source resolution. GitHub's default resolver uses /releases/latest
# (NOT /tags — that endpoint is unsorted and can return tags that were never
# published as releases). Repos with LTS release branches can instead use
# github_versionsort, which lists releases and picks the highest semver-like tag
# rather than GitHub's "latest" pointer. Grafana has a separate packages API
# because archive URLs contain build IDs that are not derivable from the version
# alone.


GITHUB_RELEASES_URL = "https://api.github.com/repos/{repo}/releases/latest"
GITHUB_RELEASES_LIST_URL = "https://api.github.com/repos/{repo}/releases?per_page=100&page={page}"
GRAFANA_VERSIONS_URL = "https://grafana.com/api/grafana/versions"
GRAFANA_PACKAGES_URL = "https://grafana.com/api/grafana/versions/{version}/packages"


def _get_json(url, timeout=10, headers=None):
    kwargs = {"timeout": timeout}
    if headers:
        kwargs["headers"] = headers
    response = requests.get(url, **kwargs)
    response.raise_for_status()
    return response.json()


# --- on-disk resolve cache (rate-limit + resilience) --------------------------
#
# Resolution runs at render time. Rendering for many minions on one host (master
# / salt-ssh controller), or repeated salt-ssh runs, would otherwise hit a fresh
# API request every time and blow the unauthenticated GitHub limit (60 req/hr/IP).
# A small TTL'd file cache, shared across render PROCESSES on that host, collapses
# them into one request per URL per TTL, and serves the last-known value if a
# refresh fails (so a GitHub blip / rate-limit doesn't fail the render).
#
# KNOWN UNHAPPY PATH (accepted): minions that render locally behind a shared NAT
# egress IP share the rate-limit budget but NOT this filesystem, so the cache
# can't help them. Use a GitHub token there. See WHITEPAPER.md §10.


def _cache_path(cache_dir, url):
    digest = hashlib.sha256(url.encode("utf-8")).hexdigest()
    return os.path.join(cache_dir, "resolve", digest + ".json")


def _read_cache_entry(path):
    try:
        with open(path, "r") as handle:
            return json.load(handle)
    except (IOError, OSError, ValueError):
        return None


def _cache_fresh(entry, ttl):
    return isinstance(entry, dict) and (time.time() - entry.get("at", 0)) < ttl


def _atomic_write_json(path, payload):
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".tmp_")
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(payload, handle)
        os.rename(tmp, path)  # atomic on POSIX, same filesystem
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


class _file_lock:
    """Cross-process advisory lock (flock); auto-released on close/process exit."""

    def __init__(self, path):
        self.path = path
        self.fd = None

    def __enter__(self):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        self.fd = os.open(self.path, os.O_CREAT | os.O_RDWR, 0o644)
        fcntl.flock(self.fd, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        fcntl.flock(self.fd, fcntl.LOCK_UN)
        os.close(self.fd)


def cached_get_json(url, cache_dir, ttl, timeout=10, headers=None):
    """JSON GET with an on-disk TTL cache shared across render processes.

    Fast path: a fresh entry is read without locking. On a cold/expired entry an
    flock serializes contenders so only one process makes the real request
    (re-checked after acquiring the lock - someone may have just filled it); the
    result is written atomically. If the refresh fails but a (stale) entry exists,
    the stale value is served rather than failing the render; a failure with no
    cache at all propagates. See the cache-section comment for the NAT caveat.
    """
    path = _cache_path(cache_dir, url)

    entry = _read_cache_entry(path)
    if _cache_fresh(entry, ttl):
        return entry["data"]

    with _file_lock(path + ".lock"):
        entry = _read_cache_entry(path)  # double-check under lock
        if _cache_fresh(entry, ttl):
            return entry["data"]
        try:
            # headers (e.g. auth) affect the request, not the key: the response
            # for a URL is the same regardless of which token fetched it.
            data = _get_json(url, timeout, headers)
            _atomic_write_json(path, {"at": time.time(), "data": data})
            return data
        except Exception:
            if entry is not None:
                log.warning("binsvc: resolve refresh failed, serving stale cache for %s", url)
                return entry["data"]
            raise


def _get_json_via_context(url, context, headers=None):
    """Fetch JSON, honoring an optional on-disk cache configured in `context`
    (`cache_dir` + `resolve_cache_ttl`). Without a usable cache config, falls back
    to a direct request - so resolvers don't care whether caching is enabled.
    `headers` is the resolver's business (e.g. the GitHub auth header) - kept out
    of the cache key on purpose."""
    cache_dir = context.get("cache_dir")
    ttl = context.get("resolve_cache_ttl", 0)
    if cache_dir and ttl and ttl > 0:
        return cached_get_json(url, cache_dir, ttl, headers=headers)
    return _get_json(url, headers=headers)


def repo_from_source(source):
    """Pull 'owner/repo' out of a github.com release/archive URL."""
    return "/".join(source.split("/")[3:5])


def repo_url(template, source):
    """Fill a '{repo}' URL template from a release/archive source URL."""
    return template.format(repo=repo_from_source(source))


def latest_from_release(body, strip=("-cluster",)):
    """GitHub /releases/latest response body -> tag name, with known
    non-version suffixes (e.g. VictoriaMetrics' '-cluster' builds) stripped."""
    tag = body["tag_name"]
    for suffix in strip:
        tag = tag.replace(suffix, "")
    return tag


def _github_headers(context):
    token = (context or {}).get("github_token")
    return {"Authorization": "Bearer {}".format(token)} if token else None


def _version_key(tag, strip=("-cluster",)):
    for suffix in strip:
        tag = tag.replace(suffix, "")
    numbers = re.findall(r"\d+", tag.lstrip("v"))
    return tuple(int(part) for part in numbers) if numbers else None


def github_latest(svc, context=None):
    """Latest published GitHub release tag (e.g. 'v1.50.0'); strips -cluster.
    Resolves only `version: latest`, and needs a source URL to derive the repo;
    returns None (nothing to resolve) otherwise. An optional `github_token` in
    context is sent as a Bearer auth header (lifts the 60->5000 req/hr limit) -
    GitHub only, never to other resolvers' endpoints."""
    if svc.get("version") != "latest" or "source" not in svc:
        return None
    context = context or {}
    headers = _github_headers(context)
    body = _get_json_via_context(repo_url(GITHUB_RELEASES_URL, svc["source"]), context, headers)
    return {"version": latest_from_release(body)}


def github_versionsort_latest(svc, context=None):
    """Highest semver-like published GitHub release tag.

    Use for repos whose GitHub "latest" pointer can point at an LTS branch. This
    still reads releases, not tags, so it ignores repo tags that were never
    published as downloadable releases.
    """
    if svc.get("version") != "latest" or "source" not in svc:
        return None

    context = context or {}
    headers = _github_headers(context)
    template = GITHUB_RELEASES_LIST_URL.replace("{repo}", repo_from_source(svc["source"]))
    candidates = []
    page = 1
    while True:
        releases = _get_json_via_context(template.format(page=page), context, headers)
        for release in releases:
            if release.get("draft") or release.get("prerelease"):
                continue
            tag = latest_from_release(release)
            key = _version_key(tag)
            if key is not None:
                candidates.append((key, tag))
        if len(releases) < 100:
            break
        page += 1

    if not candidates:
        raise RuntimeError("no version-like GitHub releases found for {}".format(repo_from_source(svc["source"])))
    return {"version": max(candidates, key=lambda item: item[0])[1]}


def _grafana_download_url(package):
    for link in package.get("links", []):
        if link.get("rel") == "download":
            return link.get("href")
    return package.get("url")


def grafana_latest(svc, context=None):
    """Resolve Grafana to a concrete stable version and API-provided tarball URL.

    grafana.com/api/grafana/versions is newest-first but includes nightly/beta,
    so `latest` filters channels.stable. Archive URLs include a build-id segment
    that is only exposed by /versions/<version>/packages, so concrete versions
    also go through the packages API. Returns None only when a concrete version
    already has a source filled (nothing left to resolve).
    """
    if svc.get("version") != "latest" and svc.get("source"):
        return None

    context = context or {}
    osarch = context.get("osarch")
    if not osarch:
        raise ValueError("grafana version_resolver requires osarch in context")

    version = svc.get("version")
    if version == "latest":
        version = None
        for item in _get_json_via_context(GRAFANA_VERSIONS_URL, context).get("items", []):
            if item.get("channels", {}).get("stable"):
                version = item["version"]
                break
        if not version:
            raise RuntimeError("no stable grafana version found in versions API")

    packages_url = GRAFANA_PACKAGES_URL.format(version=version)
    for package in _get_json_via_context(packages_url, context).get("items", []):
        if package.get("os") == "linux" and package.get("arch") == osarch:
            source = _grafana_download_url(package)
            if not source:
                raise RuntimeError("grafana package has no download URL: {}".format(version))
            resolved = {"version": version, "source": source}
            if package.get("sha256"):
                resolved["source_hash"] = "sha256={}".format(package["sha256"])
            return resolved

    raise RuntimeError("no grafana linux package found for arch {!r} and version {!r}".format(osarch, version))


VERSION_RESOLVERS = {
    "github": github_latest,
    "github_versionsort": github_versionsort_latest,
    "grafana": grafana_latest,
}


def resolve_latest(svc_settings, resolver_name, context=None):
    """Dispatch to the named resolver and apply its settings patch.

    Each resolver owns its own "is there anything to resolve?" decision and
    returns None when there isn't — so this stays free of per-resolver special
    cases. Returns a new dict (with `version`/`tag` and any source/source_hash
    the resolver supplied) when a patch is applied, else svc_settings unchanged.
    """
    resolver = VERSION_RESOLVERS.get(resolver_name)
    if resolver is None:
        raise ValueError("unknown version_resolver: {!r}".format(resolver_name))

    patch = resolver(svc_settings, context or {})
    if not patch:
        return svc_settings

    resolved = dict(svc_settings)
    resolved.update(patch)
    resolved["tag"] = resolved["version"]
    return resolved


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


# ── config ────────────────────────────────────────────────────────────────────
# Render a config-file body from structured `contents` in a chosen format.
# Kept in lib.py so format behavior is unit-tested without a minion.


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


# ── nginx ─────────────────────────────────────────────────────────────────────
# Pure nginx-vhost normalization used by blocks/nginx_vhost.sls.


ACME_CERT_DIR = "/opt/acme/cert"


def acme_cert_paths(vhost_name, first_domain, cert_dir=ACME_CERT_DIR):
    """Return the fullchain/key paths written by acme's verify_and_issue.sh."""
    base = "{}/{}_{}".format(cert_dir, vhost_name, first_domain)
    return base + "_fullchain.cer", base + "_key.key"


def resolve_nginx_servers(nginx, vhost_name):
    """Validate and normalize nginx['servers'] into render-ready dicts.

    Each server has names plus one TLS source: acme_account, ssl_cert+ssl_key,
    or neither. ACME cert paths are derived from vhost_name and first domain.
    """
    out = []
    for idx, server in enumerate(nginx.get("servers", [])):
        names = server.get("names")
        if not names or not isinstance(names, list):
            raise ValueError(
                "nginx server #{} for vhost {!r} needs a non-empty 'names' list"
                .format(idx, vhost_name))

        acme = server.get("acme_account")
        cert = server.get("ssl_cert")
        key = server.get("ssl_key")

        if acme and (cert or key):
            raise ValueError(
                "nginx server {!r} sets both acme_account and ssl_cert/ssl_key "
                "- pick one TLS source".format(names[0]))
        if bool(cert) != bool(key):
            raise ValueError(
                "nginx server {!r} must set both ssl_cert and ssl_key, got only one"
                .format(names[0]))

        entry = {
            "names": names,
            "tls": False,
            "acme_account": None,
            "ssl_cert": None,
            "ssl_key": None,
        }
        if acme:
            cert, key = acme_cert_paths(vhost_name, names[0])
            entry.update(tls=True, acme_account=acme, ssl_cert=cert, ssl_key=key)
        elif cert:
            entry.update(tls=True, ssl_cert=cert, ssl_key=key)
        out.append(entry)
    return out


# ── systemd ───────────────────────────────────────────────────────────────────
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
    `{prefix}{flag}={value}`; raw string entries render as-is. `prefix` defaults
    to the short flag form.
    """
    if isinstance(args, str):
        return args
    if isinstance(args, dict):
        items = [("{}{}={}".format(prefix, key, value)) for key, value in args.items()]
    else:
        items = []
        for entry in args:
            if isinstance(entry, str):
                items.append(entry)
            else:
                items.extend("{}{}={}".format(prefix, key, value) for key, value in entry.items())
    return " ".join(items)
