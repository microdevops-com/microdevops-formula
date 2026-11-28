"""appsvc lib/web.py

Php-fpm pools, nginx vhosts and the logrotate config composed from their logs.

Pure Python, no Salt imports: init.sls and the blocks import it with
`from salt://appsvc/lib/web.py import ...` (one line per import - that is all
the pyobjects renderer parses), and tests load it through tests/conftest.py.
"""

import fnmatch
import re

from salt://appsvc/lib/core.py import _KEY_RE, _check_unknown_keys, check_map_key


# ── php-fpm ───────────────────────────────────────────────────────────────────
# Pool files only (never PHP installation). Used by blocks/php_fpm.sls.

PHP_POOL_KEYS = ("version", "name", "user", "group", "listen", "listen_owner",
                 "listen_group", "listen_mode", "log", "reload", "config")
PHP_LOG_KEYS = ("error", "slow", "slow_timeout", "slow_trace_depth")
PHP_SLOW_TIMEOUT = 10        # seconds, when log.slow is set
PHP_SLOW_TRACE_DEPTH = 0
_PHP_DURATION_RE = re.compile(r"^[1-9]\d*[smhd]?$")


def _log_map(section, key, item, allowed):
    """The entry's `log` mapping ({} when absent), unknown keys rejected."""
    log = item.get("log")
    if log is None:
        return {}
    if not isinstance(log, dict):
        raise ValueError("{}:{}: `log` must be a mapping ({}), got {!r}".format(
            section, key, ", ".join(allowed), log))
    _check_unknown_keys(section, "{}.log".format(key), log, allowed)
    return log


def _php_slow_log(key, log):
    """(slow_log|None, timeout|None, trace_depth|None) from a pool's `log`.
    Timeout: positive int seconds, or a php-fpm duration string ("5s", "1m")."""
    slow = log.get("slow") or None
    tuning = [name for name in ("slow_timeout", "slow_trace_depth") if log.get(name) is not None]
    if not slow:
        if tuning:
            raise ValueError("php_fpm.pools:{}: log.{} needs log.slow (the slowlog path)".format(
                key, "/".join(tuning)))
        return None, None, None
    timeout = log.get("slow_timeout", PHP_SLOW_TIMEOUT)
    if isinstance(timeout, bool) or not (
            (isinstance(timeout, int) and timeout > 0)
            or (isinstance(timeout, str) and _PHP_DURATION_RE.match(timeout))):
        raise ValueError("php_fpm.pools:{}: log.slow_timeout must be positive seconds or a "
                         "duration like \"5s\"/\"1m\", got {!r}".format(key, timeout))
    depth = log.get("slow_trace_depth", PHP_SLOW_TRACE_DEPTH)
    if isinstance(depth, bool) or not isinstance(depth, int) or depth < 0:
        raise ValueError("php_fpm.pools:{}: log.slow_trace_depth must be an integer >= 0, "
                         "got {!r}".format(key, depth))
    return slow, "{}s".format(timeout) if isinstance(timeout, int) else timeout, depth
PHP_DEFAULT_LISTEN = "/run/php/php{version}-fpm-{pool_name}.sock"
_PHP_VERSION_RE = re.compile(r"^\d+\.\d+$")


def normalize_php_pools(pools, instance_name, user_name, user_group):
    """Turn the `php_fpm.pools` keyed map into an ordered list of fully resolved
    dicts (key, name, version, user, group, listen, listen_owner, listen_group,
    listen_mode, error_log|None, slow_log|None, slow_timeout|None,
    slow_trace_depth|None, reload, config, path) - from pillar `log.error`,
    `log.slow`, `log.slow_timeout`, `log.slow_trace_depth`. `listen` may use
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

        log = _log_map("php_fpm.pools", key, item, PHP_LOG_KEYS)
        error_log = log.get("error") or None
        slow_log, slow_timeout, slow_trace_depth = _php_slow_log(key, log)
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
            "slow_log": slow_log,
            "slow_timeout": slow_timeout,
            "slow_trace_depth": slow_trace_depth,
            "reload": bool(item.get("reload", True)),
            "config": config,
            "path": "/etc/php/{}/fpm/pool.d/{}.conf".format(version, name),
        })
    return result


def php_fpm_sockets(settings, instance_name):
    """{pool_key: socket} for the instance's pools - the same map the php_fpm
    block returns, computed without emitting states (for a filtered apply that
    renders nginx vhosts but skips php_fpm)."""
    conf = settings.get("php_fpm") or {}
    user = settings.get("user") or {}
    user_name = user.get("name", "root")
    pools = normalize_php_pools(conf.get("pools"), instance_name, user_name, user.get("group", user_name))
    return {pool["key"]: pool["listen"] for pool in pools}


def render_php_pool(pool):
    """Render one normalized pool to a pool.d file body (same shape as
    app/files/php-generic/pool.conf). error_log / slowlog lines only when set;
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
    if pool["slow_log"]:
        lines += ["",
                  "slowlog = {}".format(pool["slow_log"]),
                  "request_slowlog_timeout = {}".format(pool["slow_timeout"]),
                  "request_slowlog_trace_depth = {}".format(pool["slow_trace_depth"])]
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
                    "template", "vars", "log", "auth_basic")
NGINX_LOG_KEYS = ("access", "error")
NGINX_RESERVED_CONTEXT = ("vhost_name", "domain", "names", "ssl_cert", "ssl_key",
                          "access_log", "error_log", "htpasswd_file", "php_fpm_sockets")


def acme_cert_paths(vhost_name, first_domain, cert_dir=ACME_CERT_DIR):
    """Return the fullchain/key paths written by acme's verify_and_issue.sh."""
    base = "{}/{}_{}".format(cert_dir, vhost_name, first_domain)
    return base + "_fullchain.cer", base + "_key.key"


def normalize_nginx_vhosts(nginx, instance_name, php_sockets=None):
    """Validate `nginx.vhosts` (keyed map) into an ordered list of render-ready
    dicts: key, name, names, domain, tls, acme_account, ssl_cert, ssl_key,
    upstream|None, template|None, vars, access_log, error_log (from pillar
    `log.access` / `log.error`, default /var/log/nginx/<name>.*.log), auth_basic (list),
    htpasswd_file|None. ACME cert paths derive from `name` + the first domain.

    Raises ValueError on unknown keys (the pre-vhosts top-level shape is
    reported by compat.py), missing/empty `names`, not exactly one
    of upstream/template, `vars` without template, ambiguous or partial TLS,
    or a bad key/name charset. `php_sockets` is accepted for signature symmetry
    with the template context and is not used here."""
    nginx = nginx or {}
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
        log = _log_map("nginx.vhosts", key, item, NGINX_LOG_KEYS)

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
            "access_log": log.get("access") or "/var/log/nginx/{}.access.log".format(name),
            "error_log": log.get("error") or "/var/log/nginx/{}.error.log".format(name),
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
        kept = take([pool["error_log"], pool.get("slow_log")], "php pool " + pool["key"])
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
