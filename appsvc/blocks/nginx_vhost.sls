#!pyobjects
# vim: set ft=python:
from salt://appsvc/lib.py import normalize_nginx_vhosts, nginx_template_context

# Built explicitly, not taken from pyobjects' injected globals: pyobjects only
# injects factories for state modules that load on the *rendering* host, and
# under salt-ssh that is the master/container, which may lack the binary the
# module's __virtual__ needs (htpasswd -> "name 'Webutil' is not defined").
# The target still runs the real state; render no longer depends on the master.
from salt.utils.pyobjects import StateFactory
Webutil = StateFactory("webutil")

# nginx vhosts, one server group per `nginx.vhosts.<key>`: a built-in
# reverse-proxy template (`upstream`) or a custom jinja `template`, optional TLS
# via ACME DNS issuance or operator-supplied certs, optional HTTP basic auth.
# Driven by `settings["nginx"]`:
#
#   nginx:
#     manage: true
#     vhosts:
#       app:
#         # name: "<instance>_<key>"   default; file, upstream, ACME, log name
#         names: [app.example.com]
#         acme_account: example_com    # OR ssl_cert + ssl_key, OR neither
#         upstream: "127.0.0.1:9000"   # OR template: salt://... (+ vars: {...})
#         auth_basic:
#           - {username: admin, password: "..."}


def nginx_vhost(prefix, settings, php_sockets=None):
    """Render the instance's nginx vhosts, issue ACME DNS certs where requested,
    enable them and reload nginx once on change. A no-op unless `nginx.manage`
    is true. `php_sockets` ({pool_key: socket}, from php_fpm) is exposed to
    custom templates as `php_fpm_sockets`."""

    nginx = settings.get("nginx", {})

    if not nginx.get("manage", False):
        return

    sid = "_".join(prefix + ["nginx"])
    vhosts = normalize_nginx_vhosts(nginx, prefix[-1], php_sockets)

    if any(v["auth_basic"] for v in vhosts):
        File.directory(sid + "_htpasswd_dir", name="/etc/nginx/htpasswd")

    acme_requires = []
    changed = []
    for vhost in vhosts:
        vid = "{}_{}".format(sid, vhost["key"])
        vhost_path = "/etc/nginx/sites-available/{}.conf".format(vhost["name"])
        enabled_path = "/etc/nginx/sites-enabled/{}.conf".format(vhost["name"])

        for auth in vhost["auth_basic"]:
            Webutil.user_exists(vid + "_basic_auth_" + auth["username"],
                                name=auth["username"], password=auth["password"],
                                htpasswd_file=vhost["htpasswd_file"],
                                force=True)

        vhost_requires = []
        if vhost["acme_account"]:
            Cmd.run(vid + "_acme",
                    name="/opt/acme/home/{}/verify_and_issue.sh {} {}".format(
                        vhost["acme_account"], vhost["name"], " ".join(vhost["names"])),
                    shell="/bin/bash",
                    success_retcodes=[2])
            acme_requires.append(Cmd(vid + "_acme"))
            # The vhost names the cert files: never enable it before they
            # exist, or a failed issuance leaves a site that breaks the next
            # `nginx -t` for every vhost on the host.
            vhost_requires.append(Cmd(vid + "_acme"))

        if vhost["template"]:
            source = vhost["template"]
            context = nginx_template_context(vhost, php_sockets)
        else:
            source = "salt://appsvc/files/nginx/vhost.jinja"
            context = {"vhost": vhost}

        File.managed(vid + "_vhost",
                     name=vhost_path,
                     source=source,
                     template="jinja",
                     context=context,
                     require=vhost_requires)

        File.symlink(vid + "_enabled", name=enabled_path, target=vhost_path,
                     require=[File(vid + "_vhost")])

        changed += [File(vid + "_vhost"), File(vid + "_enabled")]

    Cmd.run(sid + "_reload",
            name="nginx -t && nginx -s reload",
            require=acme_requires,
            onchanges=changed)
