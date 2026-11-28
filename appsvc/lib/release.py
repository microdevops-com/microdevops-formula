"""appsvc lib/release.py

The `svc` path: fetch kinds and target paths, archive extraction, the managed
venv, and "latest" version resolution (GitHub/Grafana resolvers, resolve cache)
- the only module that talks to the network.

Pure Python, no Salt imports: init.sls and the blocks import it with
`from salt://appsvc/lib/release.py import ...` (one line per import - that is all
the pyobjects renderer parses), and tests load it through tests/conftest.py.
"""

import fcntl
import hashlib
import json
import logging
import os
import re
import tempfile
import time

import requests

log = logging.getLogger(__name__)


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
