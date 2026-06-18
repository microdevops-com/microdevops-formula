"""binsvc lib — all pure Python helpers for the binsvc formula.

Imported via `from salt://binsvc/lib.py import ...` (no sys.path or hardcoded
FORMULA_DIR needed). `init.sls` imports the helpers it uses directly, and block
files that need helpers carry their own top-level `from salt://...` imports so
pyobjects populates each block's frozen globals during that block's import.
Directly importable by pytest for unit tests.

Sections: substitute · merge · fetch · release · systemd
"""

import copy
import fcntl
import hashlib
import json
import logging
import os
import tempfile
import time

import requests

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
# Version/source resolution. GitHub uses /releases/latest (NOT /tags — that
# endpoint is unsorted and for VictoriaMetrics/VictoriaLogs returns tags that
# were never published as releases; /releases/latest is what GitHub itself
# labels "Latest"). Grafana has a separate packages API because archive URLs
# contain build IDs that are not derivable from the version alone.


GITHUB_RELEASES_URL = "https://api.github.com/repos/{repo}/releases/latest"
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


def github_latest(svc, context=None):
    """Latest published GitHub release tag (e.g. 'v1.50.0'); strips -cluster.
    Resolves only `version: latest`, and needs a source URL to derive the repo;
    returns None (nothing to resolve) otherwise. An optional `github_token` in
    context is sent as a Bearer auth header (lifts the 60->5000 req/hr limit) -
    GitHub only, never to other resolvers' endpoints."""
    if svc.get("version") != "latest" or "source" not in svc:
        return None
    context = context or {}
    token = context.get("github_token")
    headers = {"Authorization": "Bearer {}".format(token)} if token else None
    body = _get_json_via_context(repo_url(GITHUB_RELEASES_URL, svc["source"]), context, headers)
    return {"version": latest_from_release(body)}


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


VERSION_RESOLVERS = {"github": github_latest, "grafana": grafana_latest}


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
    """Merge `args` layers (each a `{flag: value}` mapping or an ordered list
    of single-key mappings) by flag name, later layers winning. Lets an
    instance override e.g. just `httpListenAddr` from a preset's `args`
    without restating `storageDataPath`/`retentionPeriod`/etc. A flag keeps
    the position of its first appearance; new flags are appended.

    Falls back to returning the last non-empty layer untouched when any single
    layer repeats a flag name (e.g. several `remoteWrite.url` entries): by-name
    merging of genuinely repeated flags is ambiguous."""
    def pairs_of(layer):
        if not layer:
            return []
        if isinstance(layer, dict):
            return list(layer.items())
        return [pair for entry in layer for pair in entry.items()]

    layer_pairs = [pairs_of(layer) for layer in layers if layer]

    if any(len({key for key, _ in pairs}) != len(pairs) for pairs in layer_pairs):
        return [{key: value} for key, value in layer_pairs[-1]] if layer_pairs else []

    order = []
    values = {}
    for pairs in layer_pairs:
        for key, value in pairs:
            if key not in values:
                order.append(key)
            values[key] = value
    return [{key: values[key]} for key in order]


def join_args(args):
    """Turn `{flag: value}` (or an ordered list of single-key mappings, needed
    when the same flag must repeat) into a `-flag=value ...` string."""
    if isinstance(args, dict):
        items = list(args.items())
    else:
        items = [pair for entry in args for pair in entry.items()]
    return " ".join("-{}={}".format(key, value) for key, value in items)
