#!pyobjects
# vim: set ft=python:

from salt://appsvc/lib/web.py import normalize_php_pools, render_php_pool, php_reload_command

# php-fpm pools only - this block never installs PHP. Driven by
# `settings["php_fpm"]["pools"]` (keyed map, see presets/generic.yaml):
#
#   php_fpm:
#     pools:
#       web:
#         version: "8.3"            # required, MUST be a quoted string
#         error_log: "{install_dir}/log/php/web.error.log"
#         config: |
#           pm = dynamic
#           pm.max_children = 20


def php_fpm(prefix, settings):
    """Write one pool.d file per pool and reload each affected php<ver>-fpm
    once, only when one of its pool files changed. Removing a pool from pillar
    does NOT delete its file. Returns {pool_key: socket_path} for nginx_vhost
    ({} when no pools are declared). Does not feed `changed`: php-fpm is not
    the instance's systemd unit."""
    conf = settings.get("php_fpm") or {}
    user = settings.get("user") or {}
    user_name = user.get("name", "root")
    user_group = user.get("group", user_name)
    pools = normalize_php_pools(conf.get("pools"), prefix[-1], user_name, user_group)
    if not pools:
        return {}

    sid = "_".join(prefix + ["php_fpm"])
    sockets = {}
    reloading = {}
    for pool in pools:
        file_id = "{}_{}".format(sid, pool["key"])
        File.managed(file_id,
                     name=pool["path"],
                     user="root",
                     group="root",
                     mode="644",
                     contents=render_php_pool(pool))
        sockets[pool["key"]] = pool["listen"]
        if pool["reload"]:
            reloading.setdefault(pool["version"], []).append(File(file_id))

    for version, refs in reloading.items():
        Cmd.run("{}_reload_{}".format(sid, version.replace(".", "_")),
                name=php_reload_command(version),
                onchanges=refs)

    return sockets
