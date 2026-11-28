#!pyobjects
# vim: set ft=python:

from salt://appsvc/lib/web.py import logrotate_plan, normalize_nginx_vhosts, normalize_php_pools, render_logrotate

# One /etc/logrotate.d/appsvc-<instance>, composed from the logs the pillar
# already declares: php_fpm pool `log.error`/`log.slow` and nginx vhost
# `log.access`/`log.error`. No list of its own to keep in sync. Tunables live
# under `logrotate:` (see presets/generic.yaml); `logrotate.manage: false`
# turns it off.


def logrotate(prefix, settings):
    """Write the instance's logrotate config, or remove it when no declared log
    needs rotating (so a dropped vhost/pool doesn't leave a stale config
    behind). Emits states only; returns nothing."""
    conf = dict(settings.get("logrotate") or {})
    if not conf.get("manage", True):
        return

    user = settings.get("user") or {}
    user_name = user.get("name", "root")
    user_group = user.get("group", user_name)

    pools = normalize_php_pools((settings.get("php_fpm") or {}).get("pools"),
                                prefix[-1], user_name, user_group)
    nginx = settings.get("nginx") or {}
    vhosts = normalize_nginx_vhosts(nginx, prefix[-1]) if nginx.get("manage", False) else []

    plan = logrotate_plan(conf, pools, vhosts, user_name, user_group)
    sid = "_".join(prefix + ["logrotate"])
    path = "/etc/logrotate.d/appsvc-{}".format(prefix[-1])

    if not plan["stanzas"]:
        File.absent(sid, name=path)
        return

    # check_cmd validates the candidate file before it replaces the live one:
    # a broken logrotate.d entry would stop rotation for the whole host.
    File.managed(sid, name=path, contents=render_logrotate(plan, prefix[-1]),
                 user="root", group="root", mode="644",
                 check_cmd="/usr/sbin/logrotate -d")
