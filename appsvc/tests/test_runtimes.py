import pytest

from appsvc_lib.core import (
    expand,
    user_home,
)
from appsvc_lib.runtimes import (
    normalize_tools,
    nvm_plan,
    pyenv_plan,
    render_env_sh,
    runtime_layout,
    runtime_paths,
    runtime_plans,
    runtime_state_suffix,
)


# ── runtimes: layout, nvm, pyenv, tools, env_sh ───────────────────────────────

NVM_BASE = {"rev": "v0.40.1", "repo": "https://github.com/nvm-sh/nvm.git"}
PYENV_BASE = {"rev": "v2.4.0", "repo": "https://github.com/pyenv/pyenv.git", "build_pkgs": ["libssl-dev"]}


def test_runtime_layout_non_root_and_root():
    u = runtime_layout("helium", "/home/helium", "crm")
    assert u == {"nvm_dir": "/home/helium/.nvm", "pyenv_root": "/home/helium/.pyenv",
                 "tools_dir": "/home/helium/.local/bin", "env_sh": "/home/helium/.appsvc/crm.sh",
                 "profile": "/home/helium/.bashrc"}
    r = runtime_layout("root", "/root", "crm")
    assert r == {"nvm_dir": "/usr/local/nvm", "pyenv_root": "/usr/local/pyenv",
                 "tools_dir": "/usr/local/bin", "env_sh": "/etc/profile.d/appsvc-crm.sh",
                 "profile": None}


def test_runtime_paths_explicit_wins_and_profile_false():
    p = runtime_paths("helium", "/home/helium", "crm", {"dir": "{home}/node"},
                      {"root": "/opt/py"}, {"path": "/srv/e.sh", "profile": "{home}/.profile"},
                      scope={"home": "/home/helium"})
    assert (p["nvm_dir"], p["pyenv_root"], p["env_sh"], p["profile"]) == \
        ("/home/helium/node", "/opt/py", "/srv/e.sh", "/home/helium/.profile")
    assert runtime_paths("helium", "/home/helium", "crm", env_sh={"profile": False})["profile"] is None


def test_runtime_paths_errors_name_instance():
    with pytest.raises(ValueError, match="instance crm.*unknown key"):
        runtime_paths("root", "/root", "crm", env_sh={"bogus": 1})
    with pytest.raises(ValueError, match="instance crm.*profile"):
        runtime_paths("root", "/root", "crm", env_sh={"profile": 5})


def test_runtime_placeholders_resolve_in_phase2_root_and_non_root():
    for user, nvm_dir, env_sh in (({"name": "helium"}, "/home/helium/.nvm", "/home/helium/.appsvc/crm.sh"),
                                  ({}, "/usr/local/nvm", "/etc/profile.d/appsvc-crm.sh")):
        p = runtime_paths(user.get("name", "root"), user_home(user), "crm")
        scope = {"nvm_dir": p["nvm_dir"], "pyenv_root": p["pyenv_root"],
                 "tools_dir": p["tools_dir"], "env_sh": p["env_sh"]}
        out = expand({"c": ". {env_sh} && composer install", "py": "{pyenv_root}/versions/x"}, scope)
        assert out["c"] == ". {} && composer install".format(env_sh)
        assert out["py"] == p["pyenv_root"] + "/versions/x"
        assert p["nvm_dir"] == nvm_dir


def test_nvm_plan_inert_without_versions():
    layout = runtime_layout("root", "/root", "crm")
    assert nvm_plan(None, layout, "root") is None
    assert nvm_plan(dict(NVM_BASE), layout, "root") is None
    assert nvm_plan(dict(NVM_BASE, versions=[]), layout, "root") is None


def test_nvm_plan_commands_non_root():
    layout = runtime_layout("helium", "/home/helium", "crm")
    plan = nvm_plan(dict(NVM_BASE, versions=["20", "18"]), layout, "helium")
    assert plan["dir"] == "/home/helium/.nvm" and plan["user"] == "helium"
    assert plan["default"] == "20" and plan["env"] == {"NVM_DIR": "/home/helium/.nvm"}
    assert plan["installs"][0] == {
        "version": "20", "suffix": "20",
        "name": '. "/home/helium/.nvm/nvm.sh" && nvm install 20',
        "unless": '. "/home/helium/.nvm/nvm.sh" && [ "$(nvm version 20)" != "N/A" ]'}
    assert plan["default_cmd"] == {
        "name": '. "/home/helium/.nvm/nvm.sh" && nvm alias default 20',
        "unless": '[ "$(cat /home/helium/.nvm/alias/default 2>/dev/null)" = "20" ]'}
    assert nvm_plan(dict(NVM_BASE, versions=["20"]), runtime_layout("root", "/root", "c"), "root")["user"] is None
    assert plan["build_pkgs"] == []
    assert nvm_plan(dict(NVM_BASE, versions=["20"], build_pkgs=["git", "curl"]), layout, "helium")["build_pkgs"] == ["git", "curl"]


def test_nvm_plan_validation():
    layout = runtime_layout("root", "/root", "crm")
    for bad in ([20], [3.1], "20", [""], ["a b"], ["$(x)"], ["20", "20"]):
        with pytest.raises(ValueError, match="nvm"):
            nvm_plan(dict(NVM_BASE, versions=bad), layout, "root")
    with pytest.raises(ValueError, match="quote it"):
        nvm_plan(dict(NVM_BASE, versions=[20]), layout, "root")
    with pytest.raises(ValueError, match="unknown key"):
        nvm_plan(dict(NVM_BASE, versions=["20"], bogus=1), layout, "root")
    with pytest.raises(ValueError, match="absolute path"):
        nvm_plan(dict(NVM_BASE, versions=["20"], dir='/a"b'), layout, "root")
    with pytest.raises(ValueError, match="nvm:build_pkgs"):
        nvm_plan(dict(NVM_BASE, versions=["20"], build_pkgs="git"), layout, "root")


def test_pyenv_plan_commands_and_validation():
    layout = runtime_layout("helium", "/home/helium", "crm")
    plan = pyenv_plan(dict(PYENV_BASE, versions=["3.8.13", "3.10"]), layout, "helium")
    assert plan["installs"][0] == {
        "version": "3.8.13", "suffix": "3_8_13",
        "name": "PYENV_ROOT=/home/helium/.pyenv /home/helium/.pyenv/bin/pyenv install -s 3.8.13",
        "unless": "test -x /home/helium/.pyenv/versions/3.8.13/bin/python"}
    assert plan["default_cmd"]["name"] == "PYENV_ROOT=/home/helium/.pyenv /home/helium/.pyenv/bin/pyenv global 3.8.13"
    assert plan["default_cmd"]["unless"] == '[ "$(cat /home/helium/.pyenv/version 2>/dev/null)" = "3.8.13" ]'
    assert plan["build_pkgs"] == ["libssl-dev"]
    assert pyenv_plan(dict(PYENV_BASE), layout, "helium") is None
    with pytest.raises(ValueError, match="quote it"):
        pyenv_plan(dict(PYENV_BASE, versions=[3.10]), layout, "helium")
    with pytest.raises(ValueError, match="build_pkgs"):
        pyenv_plan(dict(PYENV_BASE, versions=["3.8"], build_pkgs="gcc"), layout, "helium")
    assert pyenv_plan(dict(PYENV_BASE, versions=["3.8"], root="/opt/py"), layout, "root")["root"] == "/opt/py"


def test_runtime_state_suffix():
    assert runtime_state_suffix("3.8.13") == "3_8_13"
    assert runtime_state_suffix("lts/iron") == "lts_iron"


def test_normalize_tools_defaults_and_validation():
    layout = runtime_layout("helium", "/home/helium", "crm")
    out = normalize_tools({"composer": {"source": "https://x/c.phar", "source_hash": "https://x/c.sha256"},
                           "b": {"source": "https://x/b", "mode": "700", "target": "/opt/b"}},
                          layout, "helium", "helium")
    assert out[0] == ("composer", {"name": "/home/helium/.local/bin/composer", "source": "https://x/c.phar",
                                   "source_hash": "https://x/c.sha256", "user": "helium", "group": "helium",
                                   "mode": "755", "makedirs": True})
    assert out[1][1]["name"] == "/opt/b" and out[1][1]["skip_verify"] is True and "source_hash" not in out[1][1]
    assert normalize_tools(None, layout, "u", "g") == []
    for bad in ({"a/b": {"source": "x"}}, {"..": {"source": "x"}}, {"a": {}}, {"a": {"source": "x", "z": 1}},
                {"a": {"source": "x", "target": "rel"}}, {"a": {"source": "x", "mode": 755}}, {"a": "x"}):
        with pytest.raises(ValueError):
            normalize_tools(bad, layout, "u", "g")


def test_render_env_sh_sections_and_dedup():
    body = render_env_sh({"name": "crm", "nvm_dir": "/n", "pyenv_root": "/p",
                          "tool_dirs": ["/a", "/b", "/a"]})
    assert body == (
        "# Managed by salt (appsvc instance crm) - do not edit.\n"
        'export NVM_DIR="/n"\n'
        '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"\n'
        'export PYENV_ROOT="/p"\n'
        'export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"\n'
        'export PATH="/a:/b:$PATH"\n')
    only_tools = render_env_sh({"name": "c", "tool_dirs": ["/t"]})
    assert "NVM_DIR" not in only_tools and "PYENV_ROOT" not in only_tools and "/t:$PATH" in only_tools


def _settings(**kw):
    s = {"name": "crm", "nvm": dict(NVM_BASE), "pyenv": dict(PYENV_BASE),
         "user": {"name": "helium", "group": "helium"}}
    s.update(kw)
    return s


def test_runtime_plans_inert_by_default():
    plans = runtime_plans(_settings())
    assert plans["nvm"] is None and plans["pyenv"] is None
    assert plans["tools"] == [] and plans["env_sh"] is None


def test_runtime_plans_env_sh_non_root_and_root():
    s = _settings(nvm=dict(NVM_BASE, versions=["20"]),
                  tools={"composer": {"source": "https://x/c.phar"}})
    e = runtime_plans(s)["env_sh"]
    assert (e["path"], e["owner"], e["group"], e["profile"]) == \
        ("/home/helium/.appsvc/crm.sh", "helium", "helium", "/home/helium/.bashrc")
    assert e["profile_line"] == '[ -f "/home/helium/.appsvc/crm.sh" ] && . "/home/helium/.appsvc/crm.sh"  # appsvc crm'
    assert 'export PATH="/home/helium/.local/bin:$PATH"' in e["body"]
    s["user"] = {"name": "root"}
    e = runtime_plans(s)["env_sh"]
    assert (e["path"], e["owner"], e["profile"]) == ("/etc/profile.d/appsvc-crm.sh", "root", None)
    s["shell_env"] = {"profile": False}
    s["user"] = {"name": "helium", "group": "helium"}
    assert runtime_plans(s)["env_sh"]["profile"] is None


def test_runtime_plans_errors_name_instance():
    with pytest.raises(ValueError, match="instance crm: nvm"):
        runtime_plans(_settings(nvm=dict(NVM_BASE, versions=[20])))
