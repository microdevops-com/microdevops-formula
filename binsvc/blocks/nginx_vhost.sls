#!pyobjects
# vim: set ft=python:

# Generalizes victoriametrics/nginx into an instance-name-generic reverse-proxy
# vhost: one upstream, one or more server names, optional TLS (own certs - acme
# issuance stays the caller's problem, see victoriametrics/nginx for that
# pattern) and optional HTTP basic auth. Driven entirely by `settings["nginx"]`:
#
#   nginx:
#     manage: true
#     upstream: "127.0.0.1:9428"
#     server_names: [logs.example.com]
#     ssl_cert: /opt/acme/cert/logs.example.com_fullchain.cer
#     ssl_key: /opt/acme/cert/logs.example.com_key.key
#     auth_basic:
#       - {username: admin, password: "..."}


def nginx_vhost(prefix, settings):
    """Render an nginx reverse-proxy vhost in front of the instance, enable it
    and reload nginx on change. A no-op unless `nginx.manage` is true."""

    nginx = settings.get("nginx", {})

    if not nginx.get("manage", False):
        return

    sid = "_".join(prefix + ["nginx"])
    vhost_name = nginx.get("vhost_name") or prefix[-1]
    vhost_path = "/etc/nginx/sites-available/{}.conf".format(vhost_name)
    enabled_path = "/etc/nginx/sites-enabled/{}.conf".format(vhost_name)

    if "auth_basic" in nginx:
        File.directory(sid + "_htpasswd_dir", name="/etc/nginx/htpasswd")
        for auth in nginx["auth_basic"]:
            Webutil.user_exists(sid + "_basic_auth_" + auth["username"],
                                name=auth["username"], password=auth["password"],
                                htpasswd_file="/etc/nginx/htpasswd/{}".format(vhost_name),
                                force=True)

    File.managed(sid + "_vhost",
                 name=vhost_path,
                 source="salt://binsvc/files/nginx/vhost.jinja",
                 template="jinja",
                 context={"vhost_name": vhost_name, "nginx": nginx})

    File.symlink(sid + "_enabled", name=enabled_path, target=vhost_path,
                 require=[File(sid + "_vhost")])

    Cmd.run(sid + "_reload",
            name="nginx -t && nginx -s reload",
            onchanges=[File(sid + "_vhost"), File(sid + "_enabled")])

    return [File(sid + "_vhost")]
