"""appsvc lib — all pure Python helpers for the appsvc formula.

Imported via `from salt://appsvc/lib.py import ...` (no sys.path or hardcoded
FORMULA_DIR needed). `init.sls` imports the helpers it uses directly, and block
files that need helpers carry their own top-level `from salt://...` imports so
pyobjects populates each block's frozen globals during that block's import.
Directly importable by pytest for unit tests.

Sections: substitute · merge · scrape · fetch · release · commands · home · sources · dirs · runtimes (nvm/pyenv/tools/env_sh) · cron · systemd guard · config · php-fpm · nginx · systemd
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
import shlex
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


# `fetch.sls` (formerly `fetch_archive.sls`) covers two fetch strategies:
# "archive" (download, cache, optionally tar-extract - the original shape, and
# still the right one for release tarballs) and "file" (a single script or
# binary compared as-is via File.managed - the shape a plaintext daemon like
# redis_check.py, or a bare binary, actually has). fetch_kind picks between
# them; fetch_target computes the "file" destination.

ARCHIVE_SUFFIXES = (".tar.gz", ".tgz", ".tar.bz2", ".tbz2",
                    ".tar.xz", ".txz", ".tar.zst", ".tar")

# Recognized-but-unsupported: appsvc extracts with `tar` only. Failing loud
# beats silently "downloading" a .zip and calling it an executable.
UNSUPPORTED_ARCHIVE_SUFFIXES = (".zip", ".7z", ".rar", ".gz", ".bz2", ".xz")


def source_basename(source):
    """Last path segment of a URL or path, with ?query and #fragment stripped."""
    return source.split("#", 1)[0].split("?", 1)[0].rsplit("/", 1)[-1]


def fetch_kind(svc):
    """Return "archive" or "file".

    Precedence (explicit beats inferred):
      1. svc["kind"] if set - must be "archive" or "file", else ValueError.
      2. "tar" in svc            -> "archive"
      3. basename ends with an ARCHIVE_SUFFIXES entry -> "archive"
      4. basename ends with an UNSUPPORTED_ARCHIVE_SUFFIXES entry -> ValueError
         naming the suffix and pointing at svc.kind as the override.
      5. otherwise -> "file"

    3 is checked before 4 so ".tar.gz" (which also ends in ".gz") resolves to
    archive rather than tripping the unsupported-".gz" check.
    """
    kind = svc.get("kind")
    if kind is not None:
        if kind not in ("archive", "file"):
            raise ValueError("svc.kind must be 'archive' or 'file', got {!r}".format(kind))
        return kind

    if "tar" in svc:
        return "archive"

    basename = source_basename(svc.get("source", ""))
    if basename.endswith(ARCHIVE_SUFFIXES):
        return "archive"
    if basename.endswith(UNSUPPORTED_ARCHIVE_SUFFIXES):
        raise ValueError(
            "source {!r} looks like an archive appsvc can't extract (tar only); "
            "set svc.kind explicitly to override".format(basename))
    return "file"


def fetch_target(svc, install_dir):
    """Destination path for kind "file": svc["target"] if set, else
    "{install_dir}/{source_basename(source)}". Raises ValueError when the
    source is empty - an empty source is a real preset/pillar bug (grafana's
    intentionally-empty source is filled by its resolver before this runs)."""
    if svc.get("target"):
        return svc["target"]
    source = svc.get("source", "")
    if not source:
        raise ValueError("svc.source is empty; nothing to compute a fetch target from")
    return "{}/{}".format(install_dir.rstrip("/"), source_basename(source))


# ── venv ──────────────────────────────────────────────────────────────────────
# Managed Python virtualenv for a Python-based daemon (used by blocks/venv.sls).
# Diverges from exporter/macro.jinja's venv macro on purpose:
#   - the digest covering "does the venv match the declared requirement set?"
#     is computed on the MINION at runtime (interpreter version + pip_args +
#     the actual content of every requirements file, sha256'd) - not by parsing
#     `pip freeze`. exporter's `pip freeze -r ... =~ WARNING` guard only detects
#     *missing* packages, not version-constraint drift; the digest catches both,
#     and it's the only way to cover a requirements.txt that arrives inside a
#     fetched archive, whose content render time cannot know.
#   - the interpreter-version comparison catches a distro python3 upgrade
#     (3.11 -> 3.12) silently breaking every venv on the host. exporter doesn't.
#   - venv.python (configurable, default python3) is always used explicitly -
#     stock Debian has no bare `python`.
#   - --require-virtualenv is kept from exporter.

VENV_INLINE_REQUIREMENTS_NAME = ".appsvc-requirements.txt"
VENV_STAMP_NAME = ".appsvc-requirements.sha256"


def venv_requirement_paths(venv_conf, install_dir):
    """Ordered list of `-r` paths: the inline requirements file
    ("{install_dir}/.appsvc-requirements.txt", only when venv["requirements"]
    is non-empty) followed by venv["requirements_files"]. Raises ValueError
    when both are empty - a managed venv with nothing to install is a
    preset/pillar bug, not a silently-empty no-op."""
    paths = []
    if venv_conf.get("requirements"):
        paths.append("{}/{}".format(install_dir.rstrip("/"), VENV_INLINE_REQUIREMENTS_NAME))
    paths.extend(venv_conf.get("requirements_files") or [])
    if not paths:
        raise ValueError(
            "venv.manage is true but venv.requirements and venv.requirements_files "
            "are both empty - nothing to install")
    return paths


def venv_digest_command(paths, python, pip_args):
    """Shell snippet printing a sha256 of the effective install input set:
    interpreter identity, pip_args, and the content of every requirements file
    in order. Computed on the minion at RUNTIME, not render time - a
    requirements.txt can arrive inside a fetched archive whose contents render
    time cannot know."""
    return (
        "{{ {python} -V; printf '%s\\n' '{pip_args}'; cat {paths}; }} "
        "| sha256sum | cut -d' ' -f1"
    ).format(python=python, pip_args=pip_args, paths=" ".join(paths))


def venv_guard_command(venv_conf, paths, stamp_path):
    """The Cmd.run `unless` guard: true (skip the build) when the venv exists,
    was built with the currently-configured interpreter, and its stamp matches
    the current digest. Deliberately ONE shell command chained with `&&` -
    Salt's `unless` treats a list as all-must-pass but a string as a single
    shell invocation, and a multi-command list here would silently change
    semantics if a later maintainer reordered checks."""
    venv_dir = venv_conf["dir"]
    python = venv_conf.get("python", "python3")
    pip_args = venv_conf.get("pip_args", "")
    digest = venv_digest_command(paths, python, pip_args)
    return (
        "[ -x {venv_dir}/bin/python ] "
        "&& [ \"$({venv_dir}/bin/python -V 2>&1)\" = \"$({python} -V 2>&1)\" ] "
        "&& [ \"$(cat {stamp} 2>/dev/null)\" = \"$({digest})\" ]"
    ).format(venv_dir=venv_dir, python=python, stamp=stamp_path, digest=digest)


def venv_build_command(venv_conf, paths, stamp_path):
    """The Cmd.run `name`: create (or recreate) the venv, install the declared
    requirements, and stamp the digest LAST so a failed pip install leaves no
    stamp and the next run retries.

    recreate_on_change true (default) always rebuilds with `--clear` when the
    guard fails for any reason (missing venv, wrong interpreter, or a
    requirement-set change) - stale packages from a removed requirement can't
    linger. recreate_on_change false only forces a fresh venv on the same
    "missing or wrong interpreter version" test the guard itself uses, and
    otherwise reuses the existing venv, letting pip install update packages
    in place for a plain requirement-set change.
    """
    venv_dir = venv_conf["dir"]
    python = venv_conf.get("python", "python3")
    pip_args = venv_conf.get("pip_args", "")

    if venv_conf.get("recreate_on_change", True):
        create = "{python} -m venv --clear {venv_dir}".format(python=python, venv_dir=venv_dir)
    else:
        create = (
            "[ -x {venv_dir}/bin/python ] "
            "&& [ \"$({venv_dir}/bin/python -V 2>&1)\" = \"$({python} -V 2>&1)\" ] "
            "|| {python} -m venv {venv_dir}"
        ).format(venv_dir=venv_dir, python=python)

    lines = ["set -eu", create]
    if venv_conf.get("upgrade_pip", False):
        lines.append("{venv_dir}/bin/pip install --require-virtualenv -U pip".format(venv_dir=venv_dir))

    requirement_flags = " ".join("-r {}".format(path) for path in paths)
    lines.append("{venv_dir}/bin/pip install --require-virtualenv{pip_args} {reqs}".format(
        venv_dir=venv_dir,
        pip_args=" " + pip_args if pip_args else "",
        reqs=requirement_flags,
    ))

    digest = venv_digest_command(paths, python, pip_args)
    lines.append("{} > {}".format(digest, stamp_path))

    return "\n".join(lines)


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
                log.warning("appsvc: resolve refresh failed, serving stale cache for %s", url)
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


# ── runtimes: nvm, pyenv, tools, env_sh ───────────────────────────────────────
# Per-user when the instance user is not root, global when it is. Pure
# derivation of paths, validated plans and shell strings; blocks/{nvm,pyenv,
# tools,env_sh}.sls only emit states from them.

RUNTIME_PLACEHOLDERS = ("nvm_dir", "pyenv_root", "tools_dir", "env_sh")
NVM_KEYS = ("versions", "rev", "dir", "repo")
PYENV_KEYS = ("versions", "rev", "root", "repo", "build_pkgs")
ENV_SH_KEYS = ("path", "profile")
TOOL_KEYS = ("source", "source_hash", "target", "mode")
_RUNTIME_PATH_RE = re.compile(r"^/[A-Za-z0-9_./-]+$")
_NVM_VERSION_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]*$")
_PYENV_VERSION_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def runtime_layout(settings_user, home, instance_name):
    """Default runtime paths for an instance. `settings_user` is the instance
    user NAME (user.name, "root" when unset). Non-root -> everything under the
    user's `home`; root -> global (/usr/local, /etc/profile.d). `profile` is the
    rc file that gets an env_sh source line: {home}/.bashrc for a non-root
    user, None for root (profile.d is already sourced by login shells)."""
    if (settings_user or "root") == "root":
        return {
            "nvm_dir": "/usr/local/nvm",
            "pyenv_root": "/usr/local/pyenv",
            "tools_dir": "/usr/local/bin",
            "env_sh": "/etc/profile.d/appsvc-{}.sh".format(instance_name),
            "profile": None,
        }
    home = home.rstrip("/")
    return {
        "nvm_dir": home + "/.nvm",
        "pyenv_root": home + "/.pyenv",
        "tools_dir": home + "/.local/bin",
        "env_sh": "{}/.appsvc/{}.sh".format(home, instance_name),
        "profile": home + "/.bashrc",
    }


def _conf_dict(what, conf, allowed):
    """None/{} -> {}; anything but a mapping raises; unknown keys raise."""
    if conf is None:
        return {}
    if not isinstance(conf, dict):
        raise ValueError("{} must be a mapping, got {!r}".format(what, conf))
    _check_unknown_keys(what, "", conf, allowed)
    return conf


def runtime_paths(user_name, home, instance_name, nvm=None, pyenv=None, env_sh=None, scope=None):
    """Public wrapper of _runtime_paths: errors name the instance."""
    try:
        return _runtime_paths(user_name, home, instance_name, nvm, pyenv, env_sh, scope)
    except ValueError as exc:
        raise ValueError("instance {}: {}".format(instance_name, exc)) from None


def _runtime_paths(user_name, home, instance_name, nvm=None, pyenv=None, env_sh=None, scope=None):
    """runtime_layout merged with the explicit `nvm.dir` / `pyenv.root` /
    `shell_env.path` / `shell_env.profile` (explicit wins). The settings key is
    `shell_env`, not `env_sh`: `{env_sh}` is a placeholder, and expand folds
    top-level settings keys into its scope, so a same-named key would shadow it. Returns the layout dict
    (nvm_dir, pyenv_root, tools_dir, env_sh, profile). `scope` ({home, ...}) is
    used to expand placeholders in the explicit values - init.sls calls this
    before phase 2 has expanded them. `profile: false` disables the profile line
    (-> None). Raises ValueError on a bad `env_sh` shape."""
    layout = runtime_layout(user_name, home, instance_name)
    fmt = (lambda v: _format(v, _SafeScope(scope or {})) if isinstance(v, str) else v)
    nvm = _conf_dict("nvm", nvm, NVM_KEYS)
    pyenv = _conf_dict("pyenv", pyenv, PYENV_KEYS)
    env_sh = _conf_dict("shell_env", env_sh, ENV_SH_KEYS)
    if nvm.get("dir"):
        layout["nvm_dir"] = fmt(nvm["dir"])
    if pyenv.get("root"):
        layout["pyenv_root"] = fmt(pyenv["root"])
    if env_sh.get("path"):
        layout["env_sh"] = fmt(env_sh["path"])
    if "profile" in env_sh:
        profile = env_sh["profile"]
        if profile is False:
            layout["profile"] = None
        elif isinstance(profile, str) and profile:
            layout["profile"] = fmt(profile)
        else:
            raise ValueError("env_sh:profile must be a path string or false, got {!r}".format(profile))
    return layout


def _runtime_path(what, key, path):
    """Absolute, shell-safe path (it is interpolated into double quotes)."""
    if not isinstance(path, str) or not _RUNTIME_PATH_RE.match(path):
        raise ValueError("{}: `{}` must be an absolute path of [A-Za-z0-9_./-] "
                         "characters, got {!r}".format(what, key, path))
    return path.rstrip("/") or "/"


def _runtime_versions(what, versions, version_re):
    if not isinstance(versions, list):
        raise ValueError("{}:versions must be a list of quoted strings like [\"20\"], "
                         "got {!r}".format(what, versions))
    for v in versions:
        if not isinstance(v, str):
            raise ValueError("{}:versions entry {!r} is not a string - quote it "
                             "(YAML 3.10 is the float 3.1, 20 is an int)".format(what, v))
        if not version_re.match(v):
            raise ValueError("{}:versions entry {!r} has characters outside {}".format(
                what, v, version_re.pattern))
    if len(set(versions)) != len(versions):
        raise ValueError("{}:versions has duplicates: {!r}".format(what, versions))
    return list(versions)


def runtime_state_suffix(version):
    """Version -> state-ID-safe suffix ("3.8.13" -> "3_8_13")."""
    return re.sub(r"[^A-Za-z0-9_]", "_", version)


def _runtime_common(what, conf, allowed, layout_key, conf_key, layout, user_name):
    if not conf or not conf.get("versions"):
        _conf_dict(what, conf, allowed)
        return None
    _conf_dict(what, conf, allowed)
    base = _runtime_path(what, conf_key, conf.get(conf_key) or layout[layout_key])
    for key in ("rev", "repo"):
        if not isinstance(conf.get(key), str) or not conf[key]:
            raise ValueError("{}:{} must be a non-empty string, got {!r}".format(what, key, conf.get(key)))
    return base


def nvm_plan(nvm, layout, user_name):
    """Validated nvm plan, or None when `nvm` is absent or has no `versions`
    (defaults.yaml supplies rev/repo only, so defaults stay inert). Keys: dir,
    repo, rev, versions, default (= versions[0]), user (None for root), env,
    installs [{version, suffix, name, unless}], default_cmd {name, unless}."""
    base = _runtime_common("nvm", nvm, NVM_KEYS, "nvm_dir", "dir", layout, user_name)
    if base is None:
        return None
    versions = _runtime_versions("nvm", nvm["versions"], _NVM_VERSION_RE)
    default = versions[0]
    source = '. "{}/nvm.sh"'.format(base)
    installs = []
    for v in versions:
        qv = shlex.quote(v)
        installs.append({
            "version": v,
            "suffix": runtime_state_suffix(v),
            "name": "{} && nvm install {}".format(source, qv),
            "unless": '{} && [ "$(nvm version {})" != "N/A" ]'.format(source, qv),
        })
    return {
        "dir": base,
        "repo": nvm["repo"],
        "rev": nvm["rev"],
        "versions": versions,
        "default": default,
        "user": None if (user_name or "root") == "root" else user_name,
        "env": {"NVM_DIR": base},
        "installs": installs,
        "default_cmd": {
            "name": "{} && nvm alias default {}".format(source, shlex.quote(default)),
            "unless": '[ "$(cat {}/alias/default 2>/dev/null)" = "{}" ]'.format(base, default),
        },
    }


def pyenv_plan(pyenv, layout, user_name):
    """Validated pyenv plan, or None when `pyenv` is absent or has no
    `versions`. Keys: root, repo, rev, versions, default (= versions[0]), user
    (None for root), build_pkgs, env, installs [{version, suffix, name,
    unless}], default_cmd {name, unless}."""
    base = _runtime_common("pyenv", pyenv, PYENV_KEYS, "pyenv_root", "root", layout, user_name)
    if base is None:
        return None
    versions = _runtime_versions("pyenv", pyenv["versions"], _PYENV_VERSION_RE)
    default = versions[0]
    pkgs = pyenv.get("build_pkgs") or []
    if not isinstance(pkgs, list) or not all(isinstance(p, str) and p for p in pkgs):
        raise ValueError("pyenv:build_pkgs must be a list of package names, got {!r}".format(pkgs))
    installs = []
    for v in versions:
        installs.append({
            "version": v,
            "suffix": runtime_state_suffix(v),
            "name": "PYENV_ROOT={r} {r}/bin/pyenv install -s {v}".format(r=base, v=shlex.quote(v)),
            "unless": "test -x {}/versions/{}/bin/python".format(base, v),
        })
    return {
        "root": base,
        "repo": pyenv["repo"],
        "rev": pyenv["rev"],
        "versions": versions,
        "default": default,
        "user": None if (user_name or "root") == "root" else user_name,
        "build_pkgs": list(pkgs),
        "env": {"PYENV_ROOT": base},
        "installs": installs,
        "default_cmd": {
            "name": "PYENV_ROOT={r} {r}/bin/pyenv global {v}".format(r=base, v=shlex.quote(default)),
            "unless": '[ "$(cat {}/version 2>/dev/null)" = "{}" ]'.format(base, default),
        },
    }


def normalize_tools(tools, layout, user_name, user_group):
    """`tools` keyed map -> ordered [(key, File.managed kwargs)]. Defaults:
    target {tools_dir}/<key>, mode "755" (must be a string), user/group = the
    instance user/group, makedirs true; `source_hash` -> verified download,
    otherwise skip_verify (same choice as fetch's file kind). Raises
    ValueError on a bad key, unknown keys, missing `source`, a non-absolute
    target or a non-string mode."""
    if not tools:
        return []
    if not isinstance(tools, dict):
        raise ValueError("tools must be a keyed map, got {!r}".format(tools))
    result = []
    for key, item in tools.items():
        check_map_key("tools", key)
        if key in (".", ".."):
            raise ValueError("tools: invalid key {!r}".format(key))
        if not isinstance(item, dict):
            raise ValueError("tools:{}: must be a mapping, got {!r}".format(key, item))
        _check_unknown_keys("tools", key, item, TOOL_KEYS)
        source = item.get("source")
        if not isinstance(source, str) or not source:
            raise ValueError("tools:{}: `source` (download URL) is required, got {!r}".format(key, source))
        target = item.get("target") or "{}/{}".format(layout["tools_dir"].rstrip("/"), key)
        if not isinstance(target, str) or not target.startswith("/"):
            raise ValueError("tools:{}: `target` must be an absolute path, got {!r}".format(key, target))
        mode = item.get("mode", "755")
        if not isinstance(mode, str):
            raise ValueError("tools:{}: `mode` must be a quoted string like \"755\", "
                             "got {!r}".format(key, mode))
        kwargs = {"name": target, "source": source, "user": user_name, "group": user_group,
                  "mode": mode, "makedirs": True}
        if item.get("source_hash"):
            kwargs["source_hash"] = item["source_hash"]
        else:
            kwargs["skip_verify"] = True
        result.append((key, kwargs))
    return result


def render_env_sh(plan):
    """Body of the generated env file. `plan`: {name, nvm_dir|None,
    pyenv_root|None, tool_dirs: [dirs]}. Only the sections that apply are
    emitted; tool dirs are de-duplicated in declaration order. Ends with a
    newline."""
    lines = ["# Managed by salt (appsvc instance {}) - do not edit.".format(plan["name"])]
    if plan.get("nvm_dir"):
        lines += ['export NVM_DIR="{}"'.format(plan["nvm_dir"]),
                  '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"']
    if plan.get("pyenv_root"):
        lines += ['export PYENV_ROOT="{}"'.format(plan["pyenv_root"]),
                  'export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"']
    dirs = []
    for d in plan.get("tool_dirs") or []:
        if d not in dirs:
            dirs.append(d)
    if dirs:
        lines.append('export PATH="{}:$PATH"'.format(":".join(dirs)))
    return "\n".join(lines) + "\n"


def runtime_plans(settings):
    """Public wrapper of _runtime_plans: errors name the instance."""
    try:
        return _runtime_plans(settings)
    except ValueError as exc:
        raise ValueError("instance {}: {}".format(settings.get("name"), exc)) from None


def _runtime_plans(settings):
    """Everything the nvm/pyenv/tools/env_sh blocks need, derived from one
    instance's expanded settings: {paths, nvm, pyenv, tools, env_sh}. `nvm` /
    `pyenv` are plans or None, `tools` is the normalize_tools list, `env_sh`
    is None when nothing is active, else {path, body, owner, group, profile,
    profile_line}. Pure; raises ValueError (naming the key) on bad input."""
    user = settings.get("user") or {}
    user_name = user.get("name", "root")
    user_group = user.get("group", user_name)
    name = settings["name"]
    paths = _runtime_paths(user_name, user_home(user), name, settings.get("nvm"),
                           settings.get("pyenv"), settings.get("shell_env"))
    nvm = nvm_plan(settings.get("nvm"), paths, user_name)
    pyenv = pyenv_plan(settings.get("pyenv"), paths, user_name)
    tools = normalize_tools(settings.get("tools"), paths, user_name, user_group)

    env_sh = None
    if nvm or pyenv or tools:
        tool_dirs = [os.path.dirname(kw["name"]) for _, kw in tools]
        path = _runtime_path("shell_env", "path", paths["env_sh"])
        per_user = user_name != "root" and not path.startswith("/etc/")
        profile = paths["profile"]
        env_sh = {
            "path": path,
            "body": render_env_sh({"name": name,
                                   "nvm_dir": nvm["dir"] if nvm else None,
                                   "pyenv_root": pyenv["root"] if pyenv else None,
                                   "tool_dirs": tool_dirs}),
            "owner": user_name if per_user else "root",
            "group": user_group if per_user else "root",
            "profile": _runtime_path("shell_env", "profile", profile) if profile else None,
            "profile_line": '[ -f "{}" ] && . "{}"  # appsvc {}'.format(path, path, name),
        }
    return {"paths": paths, "nvm": nvm, "pyenv": pyenv, "tools": tools, "env_sh": env_sh}


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


# ── systemd guard ─────────────────────────────────────────────────────────────


def check_systemd_exec(systemd, instance_name):
    """Raise ValueError when systemd is managed (the default) but
    `systemd.Service.ExecStart` is missing/empty - an app instance with no
    daemon would otherwise get a unit that cannot start."""
    systemd = systemd or {}
    if not systemd.get("manage", True):
        return
    exec_start = (systemd.get("Service") or {}).get("ExecStart")
    if isinstance(exec_start, (list, tuple)):
        exec_start = " ".join(str(e) for e in exec_start)
    if not exec_start or not str(exec_start).strip():
        raise ValueError("instance {}: systemd.manage is true but systemd.Service.ExecStart "
                         "is missing/empty - set systemd.manage: false (no daemon) "
                         "or an ExecStart".format(instance_name))


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


# ── php-fpm ───────────────────────────────────────────────────────────────────
# Pool files only (never PHP installation). Used by blocks/php_fpm.sls.

PHP_POOL_KEYS = ("version", "name", "user", "group", "listen", "listen_owner",
                 "listen_group", "listen_mode", "error_log", "reload", "config")
PHP_DEFAULT_LISTEN = "/run/php/php{version}-fpm-{pool_name}.sock"
_PHP_VERSION_RE = re.compile(r"^\d+\.\d+$")


def normalize_php_pools(pools, instance_name, user_name, user_group):
    """Turn the `php_fpm.pools` keyed map into an ordered list of fully resolved
    dicts (key, name, version, user, group, listen, listen_owner, listen_group,
    listen_mode, error_log|None, reload, config, path). `listen` may use
    {version} and {pool_name}. Raises ValueError on a bad key, unknown keys, a
    `version` that is not a "N.N" string (a YAML float like 8.10 loses its
    zero), a bad `name` charset or a non-string `listen_mode`."""
    if not pools:
        return []
    if not isinstance(pools, dict):
        raise ValueError("php_fpm.pools must be a keyed map, got {!r}".format(pools))
    result = []
    for key, item in pools.items():
        check_map_key("php_fpm.pools", key)
        if not isinstance(item, dict):
            raise ValueError("php_fpm.pools:{}: must be a mapping, got {!r}".format(key, item))
        _check_unknown_keys("php_fpm.pools", key, item, PHP_POOL_KEYS)

        version = item.get("version")
        if not isinstance(version, str):
            raise ValueError("php_fpm.pools:{}: `version` is required and must be a quoted "
                             "string like \"8.3\" (quote it: YAML 8.10 would become 8.1), "
                             "got {!r}".format(key, version))
        if not _PHP_VERSION_RE.match(version):
            raise ValueError("php_fpm.pools:{}: `version` must look like \"8.3\", "
                             "got {!r}".format(key, version))

        name = item.get("name", "{}_{}".format(instance_name, key))
        if not isinstance(name, str) or not _KEY_RE.match(name):
            raise ValueError("php_fpm.pools:{}: invalid `name` {!r} - it becomes the pool "
                             "section and file name, allowed characters are [A-Za-z0-9_.-]"
                             .format(key, name))

        listen_mode = item.get("listen_mode", "0660")
        if not isinstance(listen_mode, str):
            raise ValueError("php_fpm.pools:{}: `listen_mode` must be a quoted string like "
                             "\"0660\", got {!r}".format(key, listen_mode))

        listen = item.get("listen", PHP_DEFAULT_LISTEN)
        if not isinstance(listen, str) or not listen.startswith("/"):
            raise ValueError("php_fpm.pools:{}: `listen` must be an absolute socket path, "
                             "got {!r}".format(key, listen))
        listen = listen.replace("{version}", version).replace("{pool_name}", name)

        error_log = item.get("error_log") or None
        config = item.get("config") or ""
        if not isinstance(config, str):
            raise ValueError("php_fpm.pools:{}: `config` must be a string of raw pool "
                             "lines, got {!r}".format(key, config))

        result.append({
            "key": key,
            "name": name,
            "version": version,
            "user": item.get("user", user_name),
            "group": item.get("group", user_group),
            "listen": listen,
            "listen_owner": item.get("listen_owner", "www-data"),
            "listen_group": item.get("listen_group", "www-data"),
            "listen_mode": listen_mode,
            "error_log": error_log,
            "reload": bool(item.get("reload", True)),
            "config": config,
            "path": "/etc/php/{}/fpm/pool.d/{}.conf".format(version, name),
        })
    return result


def render_php_pool(pool):
    """Render one normalized pool to a pool.d file body (same shape as
    app/files/php-generic/pool.conf). error_log lines only when it is set;
    `config` is appended verbatim after a blank line; ends with a newline."""
    lines = [
        "[{}]".format(pool["name"]),
        "user = {}".format(pool["user"]),
        "group = {}".format(pool["group"]),
        "",
        "listen = {}".format(pool["listen"]),
        "listen.owner = {}".format(pool["listen_owner"]),
        "listen.group = {}".format(pool["listen_group"]),
        "listen.mode = {}".format(pool["listen_mode"]),
    ]
    if pool["error_log"]:
        lines += ["",
                  "php_admin_value[error_log] = {}".format(pool["error_log"]),
                  "php_admin_flag[log_errors] = on"]
    body = "\n".join(lines) + "\n"
    if pool["config"]:
        body += "\n" + pool["config"]
        if not body.endswith("\n"):
            body += "\n"
    return body


def php_reload_command(version):
    """Validate the config, then reload the versioned php-fpm unit."""
    return "php-fpm{v} -t && systemctl reload php{v}-fpm".format(v=version)


# ── nginx ─────────────────────────────────────────────────────────────────────
# Pure nginx-vhost normalization used by blocks/nginx_vhost.sls.


ACME_CERT_DIR = "/opt/acme/cert"
NGINX_VHOST_KEYS = ("name", "names", "acme_account", "ssl_cert", "ssl_key", "upstream",
                    "template", "vars", "access_log", "error_log", "auth_basic")
NGINX_OLD_SHAPE_KEYS = ("upstream", "servers", "vhost_name", "auth_basic")
NGINX_RESERVED_CONTEXT = ("vhost_name", "domain", "names", "ssl_cert", "ssl_key",
                          "access_log", "error_log", "htpasswd_file", "php_fpm_sockets")


def acme_cert_paths(vhost_name, first_domain, cert_dir=ACME_CERT_DIR):
    """Return the fullchain/key paths written by acme's verify_and_issue.sh."""
    base = "{}/{}_{}".format(cert_dir, vhost_name, first_domain)
    return base + "_fullchain.cer", base + "_key.key"


def normalize_nginx_vhosts(nginx, instance_name, php_sockets=None):
    """Validate `nginx.vhosts` (keyed map) into an ordered list of render-ready
    dicts: key, name, names, domain, tls, acme_account, ssl_cert, ssl_key,
    upstream|None, template|None, vars, access_log, error_log, auth_basic (list),
    htpasswd_file|None. ACME cert paths derive from `name` + the first domain.

    Raises ValueError on the pre-vhosts shape (top-level upstream/servers/
    vhost_name/auth_basic), unknown keys, missing/empty `names`, not exactly one
    of upstream/template, `vars` without template, ambiguous or partial TLS,
    or a bad key/name charset. `php_sockets` is accepted for signature symmetry
    with the template context and is not used here."""
    nginx = nginx or {}
    old = [k for k in NGINX_OLD_SHAPE_KEYS if k in nginx]
    if old:
        raise ValueError(
            "nginx: {} at the top level is the removed single-vhost shape. Use "
            "nginx.vhosts.<key> instead, e.g. nginx: {{manage: true, vhosts: {{<key>: "
            "{{name: <old vhost_name, keeps the file and ACME cert name>, upstream: "
            "\"127.0.0.1:9000\", names: [app.example.com], acme_account: example_com, "
            "auth_basic: [{{username: admin, password: x}}]}}}}}}".format(", ".join(old)))

    vhosts = nginx.get("vhosts")
    if not vhosts:
        raise ValueError("instance {!r}: nginx.manage is true but nginx.vhosts is empty"
                         .format(instance_name))
    if not isinstance(vhosts, dict):
        raise ValueError("nginx.vhosts must be a keyed map, got {!r}".format(vhosts))

    result = []
    for key, item in vhosts.items():
        check_map_key("nginx.vhosts", key)
        if not isinstance(item, dict):
            raise ValueError("nginx.vhosts:{}: must be a mapping, got {!r}".format(key, item))
        _check_unknown_keys("nginx.vhosts", key, item, NGINX_VHOST_KEYS)

        name = item.get("name", "{}_{}".format(instance_name, key))
        if not isinstance(name, str) or not _KEY_RE.match(name):
            raise ValueError("nginx.vhosts:{}: invalid `name` {!r} - it becomes the file, "
                             "upstream, ACME and log name, allowed characters are "
                             "[A-Za-z0-9_.-]".format(key, name))

        names = item.get("names")
        if (not names or not isinstance(names, list)
                or not all(isinstance(n, str) and n for n in names)):
            raise ValueError("nginx.vhosts:{}: `names` must be a non-empty list of "
                             "server names, got {!r}".format(key, names))

        acme = item.get("acme_account")
        cert = item.get("ssl_cert")
        ssl_key = item.get("ssl_key")
        if acme and (cert or ssl_key):
            raise ValueError("nginx.vhosts:{}: sets both acme_account and ssl_cert/ssl_key "
                             "- pick one TLS source".format(key))
        if bool(cert) != bool(ssl_key):
            raise ValueError("nginx.vhosts:{}: must set both ssl_cert and ssl_key, "
                             "got only one".format(key))

        upstream = item.get("upstream") or None
        template = item.get("template") or None
        if bool(upstream) == bool(template):
            raise ValueError("nginx.vhosts:{}: set exactly one of `upstream` (built-in "
                             "reverse proxy) or `template` (custom jinja), got {}"
                             .format(key, "both" if upstream else "neither"))
        vhost_vars = item.get("vars") or {}
        if not isinstance(vhost_vars, dict):
            raise ValueError("nginx.vhosts:{}: `vars` must be a mapping, got {!r}"
                             .format(key, vhost_vars))
        if vhost_vars and not template:
            raise ValueError("nginx.vhosts:{}: `vars` is only used with a custom `template`"
                             .format(key))

        auth_basic = item.get("auth_basic") or []
        if not isinstance(auth_basic, list):
            raise ValueError("nginx.vhosts:{}: `auth_basic` must be a list of "
                             "{{username, password}}".format(key))
        for auth in auth_basic:
            if (not isinstance(auth, dict) or not auth.get("username")
                    or "password" not in auth):
                raise ValueError("nginx.vhosts:{}: each auth_basic entry needs `username` "
                                 "and `password`, got {!r}".format(key, auth))

        entry = {
            "key": key,
            "name": name,
            "names": names,
            "domain": " ".join(names),
            "tls": False,
            "acme_account": None,
            "ssl_cert": None,
            "ssl_key": None,
            "upstream": upstream,
            "template": template,
            "vars": vhost_vars,
            "access_log": item.get("access_log", "/var/log/nginx/{}.access.log".format(name)),
            "error_log": item.get("error_log", "/var/log/nginx/{}.error.log".format(name)),
            "auth_basic": auth_basic,
            "htpasswd_file": "/etc/nginx/htpasswd/{}".format(name) if auth_basic else None,
        }
        if acme:
            cert, ssl_key = acme_cert_paths(name, names[0])
            entry.update(tls=True, acme_account=acme, ssl_cert=cert, ssl_key=ssl_key)
        elif cert:
            entry.update(tls=True, ssl_cert=cert, ssl_key=ssl_key)
        result.append(entry)
    return result


def nginx_template_context(vhost, php_sockets=None):
    """The jinja `context` for a vhost's custom template: vhost_name, domain,
    names, ssl_cert, ssl_key (empty strings without TLS), access_log, error_log,
    htpasswd_file ("" without auth_basic), php_fpm_sockets ({pool_key: socket}),
    with `vars` merged on top. A `vars` key shadowing a reserved name raises."""
    clash = sorted(k for k in vhost["vars"] if k in NGINX_RESERVED_CONTEXT)
    if clash:
        raise ValueError("nginx.vhosts:{}: `vars` key(s) {} collide with reserved template "
                         "variables ({})".format(vhost["key"], ", ".join(clash),
                                                 ", ".join(NGINX_RESERVED_CONTEXT)))
    context = {
        "vhost_name": vhost["name"],
        "domain": vhost["domain"],
        "names": vhost["names"],
        "ssl_cert": vhost["ssl_cert"] or "",
        "ssl_key": vhost["ssl_key"] or "",
        "access_log": vhost["access_log"],
        "error_log": vhost["error_log"],
        "htpasswd_file": vhost["htpasswd_file"] or "",
        "php_fpm_sockets": dict(php_sockets or {}),
    }
    context.update(vhost["vars"])
    return context


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


# ── logrotate ─────────────────────────────────────────────────────────────────
# One /etc/logrotate.d/appsvc-<instance> composed from the logs the pillar
# already declares (php pool error_log, nginx vhost access/error logs) - no
# separate list to keep in sync.

LOGROTATE_KEYS = ("manage", "rotate", "frequency", "mode", "skip")
LOGROTATE_FREQUENCIES = ("hourly", "daily", "weekly", "monthly", "yearly")
NGINX_REOPEN = "/usr/sbin/nginx -s reopen"


def php_reopen_command(version):
    """php-fpm's packaged helper (Debian/Ubuntu/ondrej) that USR1s the master."""
    helper = "/usr/lib/php/php{}-fpm-reopenlogs".format(version)
    return "if [ -x {0} ]; then {0}; fi".format(helper)


def logrotate_plan(conf, php_pools, nginx_vhosts, user_name, user_group):
    """Group the instance's declared logs into logrotate stanzas.

    `php_pools` / `nginx_vhosts` are the normalized lists from
    normalize_php_pools / normalize_nginx_vhosts (pass [] for an inactive
    block). Returns {"options": {...}, "stanzas": [{"paths", "postrotate"}]}
    with empty stanzas when there is nothing to rotate (the block then
    removes the file). Paths matching `skip` globs (default: the distro's own
    /var/log/nginx/*.log, which its logrotate config already covers) are left
    out: logrotate aborts on a log listed by two configs. A path declared twice
    within the instance raises for the same reason."""
    conf = conf or {}
    if not isinstance(conf, dict):
        raise ValueError("logrotate must be a mapping, got {!r}".format(conf))
    _check_unknown_keys("logrotate", "(block)", conf, LOGROTATE_KEYS)

    rotate = conf.get("rotate", 31)
    if not isinstance(rotate, int) or isinstance(rotate, bool) or rotate < 0:
        raise ValueError("logrotate.rotate must be a non-negative int, got {!r}".format(rotate))
    frequency = conf.get("frequency", "daily")
    if frequency not in LOGROTATE_FREQUENCIES:
        raise ValueError("logrotate.frequency {!r} not one of {}".format(
            frequency, ", ".join(LOGROTATE_FREQUENCIES)))
    mode = conf.get("mode", "640")
    if not isinstance(mode, str) or not re.match(r"^0?[0-7]{3}$", mode):
        raise ValueError("logrotate.mode must be a quoted octal string like \"640\", got {!r}".format(mode))
    skip = conf.get("skip", ["/var/log/nginx/*.log"])
    if not isinstance(skip, list):
        raise ValueError("logrotate.skip must be a list of globs, got {!r}".format(skip))

    seen = {}

    def take(paths, owner):
        kept = []
        for path in paths:
            if not path:
                continue
            if not path.startswith("/") or any(c.isspace() for c in path):
                raise ValueError("log path {!r} ({}) must be absolute without whitespace".format(path, owner))
            if any(fnmatch.fnmatch(path, glob) for glob in skip):
                continue
            if path in seen:
                raise ValueError("log {} is declared by both {} and {} - logrotate would "
                                 "abort on the duplicate".format(path, seen[path], owner))
            seen[path] = owner
            kept.append(path)
        return kept

    stanzas = []
    nginx_paths = []
    for vhost in nginx_vhosts or []:
        nginx_paths += take([vhost["access_log"], vhost["error_log"]], "nginx vhost " + vhost["key"])
    if nginx_paths:
        stanzas.append({"paths": nginx_paths, "postrotate": NGINX_REOPEN})

    by_version = {}
    for pool in php_pools or []:
        kept = take([pool["error_log"]], "php pool " + pool["key"])
        if kept:
            by_version.setdefault(pool["version"], []).extend(kept)
    for version, paths in by_version.items():
        stanzas.append({"paths": paths, "postrotate": php_reopen_command(version)})

    return {
        "options": {"rotate": rotate, "frequency": frequency, "mode": mode,
                    "user": user_name, "group": user_group},
        "stanzas": stanzas,
    }


def render_logrotate(plan, instance_name):
    """logrotate.d body for logrotate_plan's output."""
    opts = plan["options"]
    lines = ["# Managed by salt (appsvc instance {}) - do not edit.".format(instance_name)]
    for stanza in plan["stanzas"]:
        lines.append("")
        lines.extend(stanza["paths"][:-1])
        lines.append(stanza["paths"][-1] + " {")
        lines += [
            "    " + opts["frequency"],
            "    rotate {}".format(opts["rotate"]),
            "    missingok",
            "    notifempty",
            "    compress",
            "    delaycompress",
            "    create {} {} {}".format(opts["mode"], opts["user"], opts["group"]),
            "    sharedscripts",
            "    postrotate",
            "        " + stanza["postrotate"],
            "    endscript",
            "}",
        ]
    return "\n".join(lines) + "\n"
