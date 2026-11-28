import pytest
from appsvc_lib.core import merge

from appsvc_lib.web import (
    acme_cert_paths,
    logrotate_plan,
    nginx_template_context,
    normalize_nginx_vhosts,
    normalize_php_pools,
    php_fpm_sockets,
    php_reload_command,
    php_reopen_command,
    render_logrotate,
    render_php_pool,
)


# ── nginx ─────────────────────────────────────────────────────────────────────

def test_acme_cert_paths_match_acme_verify_and_issue_naming():
    assert acme_cert_paths("vmserver", "vm.example.com") == (
        "/opt/acme/cert/vmserver_vm.example.com_fullchain.cer",
        "/opt/acme/cert/vmserver_vm.example.com_key.key",
    )


def _vh(**kw):
    base = {"names": ["a.example.com"], "upstream": "127.0.0.1:9000"}
    base.update(kw)
    return base


def _norm(vhosts, instance="app", sockets=None):
    return normalize_nginx_vhosts({"manage": True, "vhosts": vhosts}, instance, sockets)


def test_nginx_vhosts_derive_acme_tls_paths_and_defaults():
    [v] = _norm({"web": _vh(names=["logs.example.com", "logs-alt.example.com"],
                            acme_account="example_com")}, "vlogs")
    assert v["key"] == "web"
    assert v["name"] == "vlogs_web"
    assert v["domain"] == "logs.example.com logs-alt.example.com"
    assert v["tls"] is True
    assert v["acme_account"] == "example_com"
    assert v["ssl_cert"] == "/opt/acme/cert/vlogs_web_logs.example.com_fullchain.cer"
    assert v["ssl_key"] == "/opt/acme/cert/vlogs_web_logs.example.com_key.key"
    assert v["upstream"] == "127.0.0.1:9000" and v["template"] is None
    assert v["access_log"] == "/var/log/nginx/vlogs_web.access.log"
    assert v["error_log"] == "/var/log/nginx/vlogs_web.error.log"
    assert v["auth_basic"] == [] and v["htpasswd_file"] is None


def test_nginx_vhost_name_override_keeps_old_cert_name():
    [v] = _norm({"x": _vh(name="vmserver", acme_account="a", names=["vm.example.com"])})
    assert v["ssl_cert"] == "/opt/acme/cert/vmserver_vm.example.com_fullchain.cer"


def test_nginx_vhosts_keep_operator_tls_plain_and_order():
    result = _norm({
        "acme": _vh(acme_account="example_com"),
        "static": _vh(ssl_cert="/cert.pem", ssl_key="/key.pem"),
        "plain": _vh(),
    })
    assert [v["key"] for v in result] == ["acme", "static", "plain"]
    assert [v["tls"] for v in result] == [True, True, False]
    assert result[1]["ssl_cert"] == "/cert.pem"
    assert result[2]["ssl_cert"] is None and result[2]["acme_account"] is None


def test_nginx_vhost_auth_basic_sets_htpasswd_file():
    [v] = _norm({"web": _vh(name="svc", auth_basic=[{"username": "admin", "password": "x"}])})
    assert v["htpasswd_file"] == "/etc/nginx/htpasswd/svc"


def test_nginx_vhosts_reject_ambiguous_and_partial_tls():
    with pytest.raises(ValueError, match="both acme_account and ssl_cert/ssl_key"):
        _norm({"w": _vh(acme_account="a", ssl_cert="/c", ssl_key="/k")})
    with pytest.raises(ValueError, match="must set both ssl_cert and ssl_key"):
        _norm({"w": _vh(ssl_cert="/c")})
    with pytest.raises(ValueError, match="must set both ssl_cert and ssl_key"):
        _norm({"w": _vh(ssl_key="/k")})


def test_nginx_vhosts_reject_bad_names():
    with pytest.raises(ValueError, match="`names` must be a non-empty list"):
        _norm({"w": {"upstream": "x:1"}})
    with pytest.raises(ValueError, match="`names` must be a non-empty list"):
        _norm({"w": _vh(names=[])})


def test_nginx_vhosts_upstream_xor_template_and_vars_need_template():
    with pytest.raises(ValueError, match="exactly one of"):
        _norm({"w": {"names": ["a.example.com"]}})
    with pytest.raises(ValueError, match="exactly one of"):
        _norm({"w": _vh(template="salt://x.conf")})
    with pytest.raises(ValueError, match="`vars` is only used with a custom"):
        _norm({"w": _vh(vars={"a": 1})})


def test_nginx_vhosts_reject_bad_key_name_unknown_key_and_empty():
    with pytest.raises(ValueError, match="invalid key"):
        _norm({"bad key": _vh()})
    with pytest.raises(ValueError, match="invalid `name`"):
        _norm({"w": _vh(name="a/b")})
    with pytest.raises(ValueError, match="unknown key"):
        _norm({"w": _vh(bogus=1)})
    with pytest.raises(ValueError, match="vhosts is empty"):
        normalize_nginx_vhosts({"manage": True}, "app")


def test_nginx_vhost_log():
    [v] = _norm({"w": _vh(log={"access": "/l/a.log", "error": "/l/e.log"})})
    assert (v["access_log"], v["error_log"]) == ("/l/a.log", "/l/e.log")
    [v] = _norm({"w": _vh(log={"error": "/l/e.log"})})        # access keeps its default
    assert (v["access_log"], v["error_log"]) == ("/var/log/nginx/app_w.access.log", "/l/e.log")
    with pytest.raises(ValueError, match="unknown key.*slow"):
        _norm({"w": _vh(log={"slow": "/l/s.log"})})
    with pytest.raises(ValueError, match="must be a mapping"):
        _norm({"w": _vh(log="/l/a.log")})
    with pytest.raises(ValueError, match="unknown key.*access_log"):
        _norm({"w": _vh(access_log="/l/a.log")})


def test_nginx_vhost_defaults_merge_and_placeholders():
    nginx = {"manage": True, "defaults": merge(_repo_defaults()["nginx"]["defaults"], {
                 "template": "salt://t/{vhost}.conf",
                 "log": {"access": "/srv/log/nginx/{vhost}.access.log"}}),
             "vhosts": {"back": {"names": ["b.example.com"]},
                        "front": {"names": ["f.example.com"], "name": "legacy_{vhost}",
                                  "log": {"error": "/srv/e.log"}}}}
    back, front = normalize_nginx_vhosts(nginx, "inst")
    assert (back["template"], back["access_log"], back["error_log"]) == \
        ("salt://t/back.conf", "/srv/log/nginx/back.access.log", "/var/log/nginx/inst_back.error.log")
    assert (front["name"], front["access_log"], front["error_log"]) == \
        ("legacy_front", "/srv/log/nginx/front.access.log", "/srv/e.log")
    with pytest.raises(ValueError, match="nginx:defaults: unknown key"):
        normalize_nginx_vhosts(dict(nginx, defaults={"names2": 1}), "inst")


def test_nginx_template_context_has_reserved_names_and_vars_on_top():
    [v] = _norm({"w": _vh(name="svc", upstream=None, template="salt://t.conf",
                          acme_account="a", vars={"port": 1})}, "app")
    ctx = nginx_template_context(v, {"w": "/run/php/x.sock"})
    assert ctx == {
        "vhost_name": "svc", "domain": "a.example.com", "names": ["a.example.com"],
        "ssl_cert": "/opt/acme/cert/svc_a.example.com_fullchain.cer",
        "ssl_key": "/opt/acme/cert/svc_a.example.com_key.key",
        "access_log": "/var/log/nginx/svc.access.log",
        "error_log": "/var/log/nginx/svc.error.log",
        "htpasswd_file": "", "php_fpm_sockets": {"w": "/run/php/x.sock"}, "port": 1,
    }


def test_nginx_template_context_empty_strings_without_tls_and_reserved_clash():
    [v] = _norm({"w": _vh(upstream=None, template="salt://t.conf")})
    ctx = nginx_template_context(v)
    assert ctx["ssl_cert"] == "" and ctx["ssl_key"] == "" and ctx["php_fpm_sockets"] == {}
    [bad] = _norm({"w": _vh(upstream=None, template="salt://t.conf", vars={"domain": "x"})})
    with pytest.raises(ValueError, match="collide with reserved"):
        nginx_template_context(bad)


# ── php-fpm ───────────────────────────────────────────────────────────────────

def _pools(pools, instance="inst"):
    return normalize_php_pools(pools, instance, "web", "webgrp")


def test_php_pools_defaults_resolved():
    [p] = _pools({"back": {"version": "8.3"}})
    assert p == {
        "key": "back", "name": "inst_back", "version": "8.3", "user": "web", "group": "webgrp",
        "listen": "/run/php/php8.3-fpm-inst_back.sock",
        "listen_owner": "www-data", "listen_group": "www-data", "listen_mode": "0660",
        "error_log": None, "slow_log": None, "slow_timeout": None, "slow_trace_depth": None,
        "reload": True, "config": "",
        "path": "/etc/php/8.3/fpm/pool.d/inst_back.conf",
    }


def test_php_pools_empty_and_order_and_overrides():
    assert _pools(None) == [] and _pools({}) == []
    result = _pools({"b": {"version": "8.1", "name": "x", "user": "u", "reload": False,
                           "listen": "/run/{pool_name}-{php_version}-{pool}.sock"},
                     "a": {"version": "8.10"}})
    assert [p["key"] for p in result] == ["b", "a"]
    assert result[0]["listen"] == "/run/x-8.1-b.sock"
    assert result[0]["user"] == "u" and result[0]["reload"] is False
    assert result[1]["path"] == "/etc/php/8.10/fpm/pool.d/inst_a.conf"


def test_php_pools_validation():
    with pytest.raises(ValueError, match="quote it"):
        _pools({"a": {"version": 8.3}})
    with pytest.raises(ValueError, match="quote it"):
        _pools({"a": {}})
    with pytest.raises(ValueError, match="must look like"):
        _pools({"a": {"version": "8"}})
    with pytest.raises(ValueError, match="invalid key"):
        _pools({"a b": {"version": "8.3"}})
    with pytest.raises(ValueError, match="unknown key"):
        _pools({"a": {"version": "8.3", "bogus": 1}})
    with pytest.raises(ValueError, match="invalid `name`"):
        _pools({"a": {"version": "8.3", "name": "a b"}})
    with pytest.raises(ValueError, match="listen_mode"):
        _pools({"a": {"version": "8.3", "listen_mode": 660}})


def test_render_php_pool_with_and_without_error_log():
    [p] = _pools({"a": {"version": "8.3", "log": {"error": "/l/e.log"},
                        "config": "pm = dynamic\npm.max_children = 20\n"}})
    assert render_php_pool(p) == (
        "[inst_a]\nuser = web\ngroup = webgrp\n\n"
        "listen = /run/php/php8.3-fpm-inst_a.sock\nlisten.owner = www-data\n"
        "listen.group = www-data\nlisten.mode = 0660\n\n"
        "php_admin_value[error_log] = /l/e.log\nphp_admin_flag[log_errors] = on\n\n"
        "pm = dynamic\npm.max_children = 20\n")
    [q] = _pools({"a": {"version": "8.3", "config": "pm = static"}})
    out = render_php_pool(q)
    assert "error_log" not in out and out.endswith("listen.mode = 0660\n\npm = static\n")


def test_php_slow_log():
    [p] = _pools({"a": {"version": "8.3", "log": {"slow": "/l/s.log"}}})
    assert (p["slow_log"], p["slow_timeout"], p["slow_trace_depth"]) == ("/l/s.log", "10s", 0)
    assert render_php_pool(p).endswith(
        "listen.mode = 0660\n\nslowlog = /l/s.log\nrequest_slowlog_timeout = 10s\n"
        "request_slowlog_trace_depth = 0\n")
    [q] = _pools({"a": {"version": "8.3", "log": {"slow": "/l/s.log", "slow_timeout": "1m",
                                                   "slow_trace_depth": 20}}})
    assert (q["slow_timeout"], q["slow_trace_depth"]) == ("1m", 20)
    [r] = _pools({"a": {"version": "8.3", "log": {"slow": "/l/s.log", "slow_timeout": 3}}})
    assert r["slow_timeout"] == "3s"


@pytest.mark.parametrize("log, error", [
    ({"slow": "/s", "slow_timeout": 0}, "slow_timeout"),
    ({"slow": "/s", "slow_timeout": "10 s"}, "slow_timeout"),
    ({"slow": "/s", "slow_timeout": True}, "slow_timeout"),
    ({"slow": "/s", "slow_trace_depth": -1}, "slow_trace_depth"),
    ({"slow": "/s", "slow_trace_depth": "5"}, "slow_trace_depth"),
    ({"access": "/a"}, "unknown key"),
    ("/l/e.log", "must be a mapping"),
])
def test_php_log_validation(log, error):
    with pytest.raises(ValueError, match=error):
        _pools({"a": {"version": "8.3", "log": log}})


def test_php_slow_tuning_unused_without_slow():
    [p] = _pools({"a": {"version": "8.3", "log": {"error": "/e", "slow_timeout": 5}}})
    assert (p["slow_log"], p["slow_timeout"]) == (None, None)
    assert "slowlog" not in render_php_pool(p)


def _repo_defaults():
    import os, yaml
    with open(os.path.join(os.path.dirname(__file__), "..", "defaults.yaml")) as f:
        return yaml.safe_load(f)


def test_php_pool_defaults_merge_and_placeholders():
    defaults = merge(_repo_defaults()["php_fpm"]["defaults"], {
        "version": "8.3",
        "log": {"error": "/srv/log/php/{pool}.error.log", "slow": "/srv/log/php/{pool_name}.slow.log"},
        "config": "php_value[x] = {php_version}\n"})
    a, b = normalize_php_pools({"a": None, "b": {"version": "8.1", "log": {"slow_timeout": "2s"}}},
                               "inst", "web", "webgrp", defaults)
    assert (a["version"], a["error_log"], a["slow_log"], a["slow_timeout"], a["slow_trace_depth"]) == \
        ("8.3", "/srv/log/php/a.error.log", "/srv/log/php/inst_a.slow.log", "10s", 0)
    assert a["config"] == "php_value[x] = 8.3\n"
    assert (b["version"], b["slow_timeout"], b["listen"]) == \
        ("8.1", "2s", "/run/php/php8.1-fpm-inst_b.sock")
    [c] = normalize_php_pools({"c": {}}, "inst", "web", "webgrp", {"version": "8.3", "name": "x_{pool}"})
    assert c["name"] == "x_c" and c["path"] == "/etc/php/8.3/fpm/pool.d/x_c.conf"
    with pytest.raises(ValueError, match="php_fpm:defaults: unknown key"):
        normalize_php_pools({"c": {}}, "inst", "web", "webgrp", {"bogus": 1})
    with pytest.raises(ValueError, match="defaults must be a mapping"):
        normalize_php_pools({"c": {}}, "inst", "web", "webgrp", "x")


def test_php_old_error_log_key_rejected():
    with pytest.raises(ValueError, match="unknown key.*error_log"):
        _pools({"a": {"version": "8.3", "error_log": "/l/e.log"}})


def test_php_reload_command():
    assert php_reload_command("8.3") == "php-fpm8.3 -t && systemctl reload php8.3-fpm"



# --- logrotate ----------------------------------------------------------------

def _pool(key, version, error_log):
    return {"key": key, "version": version, "error_log": error_log}


def _vhost(key, access_log, error_log):
    return {"key": key, "access_log": access_log, "error_log": error_log}


def test_logrotate_groups_nginx_and_php_per_version():
    plan = logrotate_plan(
        {}, [_pool("a", "8.3", "/srv/log/php/a.log"), _pool("b", "8.1", "/srv/log/php/b.log"),
             _pool("c", "8.3", "/srv/log/php/c.log")],
        [_vhost("w", "/srv/log/nginx/w.access.log", "/srv/log/nginx/w.error.log")],
        "helium", "helium")
    assert [s["paths"] for s in plan["stanzas"]] == [
        ["/srv/log/nginx/w.access.log", "/srv/log/nginx/w.error.log"],
        ["/srv/log/php/a.log", "/srv/log/php/c.log"],
        ["/srv/log/php/b.log"]]
    assert plan["stanzas"][0]["postrotate"] == "/usr/sbin/nginx -s reopen"
    assert plan["stanzas"][1]["postrotate"] == php_reopen_command("8.3")
    body = render_logrotate(plan, "crm")
    assert "/srv/log/nginx/w.access.log\n/srv/log/nginx/w.error.log {" in body
    assert "    create 640 helium helium" in body and "    rotate 31" in body
    assert body.count("postrotate") == 3


def test_logrotate_skips_distro_nginx_logs_and_pools_without_error_log():
    plan = logrotate_plan({}, [_pool("a", "8.3", None)],
                          [_vhost("w", "/var/log/nginx/w.access.log", "/var/log/nginx/w.error.log")],
                          "root", "root")
    assert plan["stanzas"] == []


def test_logrotate_includes_php_slow_log():
    pool = dict(_pool("a", "8.3", "/srv/log/php/a.log"), slow_log="/srv/log/php/a.slow.log")
    plan = logrotate_plan({}, [pool, dict(_pool("b", "8.3", None), slow_log="/srv/log/php/b.slow.log")],
                          [], "u", "u")
    assert [s["paths"] for s in plan["stanzas"]] == [
        ["/srv/log/php/a.log", "/srv/log/php/a.slow.log", "/srv/log/php/b.slow.log"]]


def test_logrotate_duplicate_path_raises():
    with pytest.raises(ValueError, match="declared by both"):
        logrotate_plan({}, [_pool("a", "8.3", "/srv/x.log")], [_vhost("w", "/srv/x.log", "/srv/y.log")],
                       "u", "u")


@pytest.mark.parametrize("conf", [{"rotate": "31"}, {"frequency": "often"}, {"mode": 640},
                                  {"skip": "/var/log/*"}, {"bogus": 1}])
def test_logrotate_rejects_bad_options(conf):
    with pytest.raises(ValueError):
        logrotate_plan(conf, [], [], "u", "u")


def test_logrotate_relative_path_raises():
    with pytest.raises(ValueError, match="absolute"):
        logrotate_plan({}, [_pool("a", "8.3", "log/a.log")], [], "u", "u")


def test_php_fpm_sockets_match_the_pools_listen():
    settings = {"user": {"name": "web", "group": "webgrp"},
                "php_fpm": {"pools": {"a": {"version": "8.3"}, "b": {"version": "8.1", "listen": "/run/x.sock"}}}}
    assert php_fpm_sockets(settings, "app") == {
        "a": [p["listen"] for p in _pools({"a": {"version": "8.3"}}, "app")][0], "b": "/run/x.sock"}
    assert php_fpm_sockets({}, "app") == {}
