"""binsvc lib — all pure Python helpers for the binsvc formula.

Imported via `from salt://binsvc/lib.py import ...` (no sys.path or hardcoded
FORMULA_DIR needed). `init.sls` imports the helpers it uses directly, and block
files that need helpers carry their own top-level `from salt://...` imports so
pyobjects populates each block's frozen globals during that block's import.
Directly importable by pytest for unit tests.

Sections: substitute · merge · fetch · release · systemd
"""

import copy
import requests


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


def version_check(binary, version):
    """`unless` guard: true (= skip re-extracting) once `binary -version`
    already reports `version`."""
    return "[[ $({} -version 2>&1) =~ {} ]]".format(binary, version)


# ── release ───────────────────────────────────────────────────────────────────
# Version/source resolution. GitHub uses /releases/latest (NOT /tags — that
# endpoint is unsorted and for VictoriaMetrics/VictoriaLogs returns tags that
# were never published as releases; /releases/latest is what GitHub itself
# labels "Latest"). Grafana has a separate packages API because archive URLs
# contain build IDs that are not derivable from the version alone.


GITHUB_RELEASES_URL = "https://api.github.com/repos/{repo}/releases/latest"
GRAFANA_VERSIONS_URL = "https://grafana.com/api/grafana/versions"
GRAFANA_PACKAGES_URL = "https://grafana.com/api/grafana/versions/{version}/packages"


def _get_json(url, timeout=10):
    response = requests.get(url, timeout=timeout)
    response.raise_for_status()
    return response.json()


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
    returns None (nothing to resolve) otherwise."""
    if svc.get("version") != "latest" or "source" not in svc:
        return None
    return {
        "version": latest_from_release(_get_json(repo_url(GITHUB_RELEASES_URL, svc["source"])))
    }


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
        for item in _get_json(GRAFANA_VERSIONS_URL).get("items", []):
            if item.get("channels", {}).get("stable"):
                version = item["version"]
                break
        if not version:
            raise RuntimeError("no stable grafana version found in versions API")

    packages_url = GRAFANA_PACKAGES_URL.format(version=version)
    for package in _get_json(packages_url).get("items", []):
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
