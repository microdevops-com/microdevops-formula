#!pyobjects
# vim: set ft=python:
from salt://binsvc/lib.py import resolve_nginx_servers

# Generic reverse-proxy vhost: one upstream, one or more server blocks, optional
# per-server TLS via ACME DNS issuance or operator-supplied certs, and optional
# top-level HTTP basic auth shared by every server block. Driven by
# `settings["nginx"]`:
#
#   nginx:
#     manage: true
#     upstream: "127.0.0.1:9428"
#     servers:
#       - names: [logs.example.com]
#         acme_account: example_com
#       - names: [logs-internal.example.com]
#         ssl_cert: /etc/ssl/certs/internal.fullchain.pem
#         ssl_key: /etc/ssl/private/internal.key
#       - names: [logs-plain.example.com]
#     auth_basic:
#       - {username: admin, password: "..."}


def nginx_vhost(prefix, settings):
    """Render an nginx reverse-proxy vhost in front of the instance, issue ACME
    DNS certs where requested, enable it and reload nginx on change. A no-op
    unless `nginx.manage` is true."""

    nginx = settings.get("nginx", {})

    if not nginx.get("manage", False):
        return

    sid = "_".join(prefix + ["nginx"])
    vhost_name = nginx.get("vhost_name") or prefix[-1]
    vhost_path = "/etc/nginx/sites-available/{}.conf".format(vhost_name)
    enabled_path = "/etc/nginx/sites-enabled/{}.conf".format(vhost_name)
    servers = resolve_nginx_servers(nginx, vhost_name)

    if "auth_basic" in nginx:
        File.directory(sid + "_htpasswd_dir", name="/etc/nginx/htpasswd")
        for auth in nginx["auth_basic"]:
            Webutil.user_exists(sid + "_basic_auth_" + auth["username"],
                                name=auth["username"], password=auth["password"],
                                htpasswd_file="/etc/nginx/htpasswd/{}".format(vhost_name),
                                force=True)

    acme_requires = []
    for idx, server in enumerate(servers):
        if server["acme_account"]:
            cmd_id = "{}_acme_{}".format(sid, idx)
            Cmd.run(cmd_id,
                    name="/opt/acme/home/{}/verify_and_issue.sh {} {}".format(
                        server["acme_account"], vhost_name, " ".join(server["names"])),
                    shell="/bin/bash",
                    success_retcodes=[2])
            acme_requires.append(Cmd(cmd_id))

    File.managed(sid + "_vhost",
                 name=vhost_path,
                 source="salt://binsvc/files/nginx/vhost.jinja",
                 template="jinja",
                 context={"vhost_name": vhost_name, "nginx": nginx, "servers": servers})

    File.symlink(sid + "_enabled", name=enabled_path, target=vhost_path,
                 require=[File(sid + "_vhost")])

    Cmd.run(sid + "_reload",
            name="nginx -t && nginx -s reload",
            require=acme_requires,
            onchanges=[File(sid + "_vhost"), File(sid + "_enabled")])

    return [File(sid + "_vhost")]
