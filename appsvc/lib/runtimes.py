"""appsvc lib/runtimes.py

Language runtimes: the per-user/global layout, nvm, pyenv, single-file tools
(composer & co.) and the generated env_sh.

Pure Python, no Salt imports: init.sls and the blocks import it with
`from salt://appsvc/lib/runtimes.py import ...` (one line per import - that is all
the pyobjects renderer parses), and tests load it through tests/conftest.py.
"""

import os
import re
import shlex

from salt://appsvc/lib/core.py import _SafeScope, _check_unknown_keys, _format, check_map_key, user_home


# ── runtimes: nvm, pyenv, tools, env_sh ───────────────────────────────────────
# Per-user when the instance user is not root, global when it is. Pure
# derivation of paths, validated plans and shell strings; blocks/{nvm,pyenv,
# tools,env_sh}.sls only emit states from them.

RUNTIME_PLACEHOLDERS = ("nvm_dir", "pyenv_root", "tools_dir", "env_sh")
NVM_KEYS = ("versions", "rev", "dir", "repo", "build_pkgs")
PYENV_KEYS = ("versions", "rev", "root", "repo", "build_pkgs")
ENV_SH_KEYS = ("path", "profile")
TOOL_KEYS = ("source", "source_hash", "target", "mode")
_RUNTIME_PATH_RE = re.compile(r"^/[A-Za-z0-9_./-]+$")
_NVM_VERSION_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]*$")
_PYENV_VERSION_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def runtime_layout(settings_user, home, instance_name):
    """Default runtime paths for an instance. `settings_user` is the instance
    user NAME (user.name, "root" when unset). Non-root -> everything under the
    user's `home`; root -> global (/usr/local, /etc/profile.d). `profile` is the
    rc file that gets an env_sh source line: {home}/.bashrc for a non-root
    user, None for root (profile.d is already sourced by login shells)."""
    if (settings_user or "root") == "root":
        return {
            "nvm_dir": "/usr/local/nvm",
            "pyenv_root": "/usr/local/pyenv",
            "tools_dir": "/usr/local/bin",
            "env_sh": "/etc/profile.d/appsvc-{}.sh".format(instance_name),
            "profile": None,
        }
    home = home.rstrip("/")
    return {
        "nvm_dir": home + "/.nvm",
        "pyenv_root": home + "/.pyenv",
        "tools_dir": home + "/.local/bin",
        "env_sh": "{}/.appsvc/{}.sh".format(home, instance_name),
        "profile": home + "/.bashrc",
    }


def _conf_dict(what, conf, allowed):
    """None/{} -> {}; anything but a mapping raises; unknown keys raise."""
    if conf is None:
        return {}
    if not isinstance(conf, dict):
        raise ValueError("{} must be a mapping, got {!r}".format(what, conf))
    _check_unknown_keys(what, "", conf, allowed)
    return conf


def runtime_paths(user_name, home, instance_name, nvm=None, pyenv=None, env_sh=None, scope=None):
    """Public wrapper of _runtime_paths: errors name the instance."""
    try:
        return _runtime_paths(user_name, home, instance_name, nvm, pyenv, env_sh, scope)
    except ValueError as exc:
        raise ValueError("instance {}: {}".format(instance_name, exc)) from None


def _runtime_paths(user_name, home, instance_name, nvm=None, pyenv=None, env_sh=None, scope=None):
    """runtime_layout merged with the explicit `nvm.dir` / `pyenv.root` /
    `shell_env.path` / `shell_env.profile` (explicit wins). The settings key is
    `shell_env`, not `env_sh`: `{env_sh}` is a placeholder, and expand folds
    top-level settings keys into its scope, so a same-named key would shadow it. Returns the layout dict
    (nvm_dir, pyenv_root, tools_dir, env_sh, profile). `scope` ({home, ...}) is
    used to expand placeholders in the explicit values - init.sls calls this
    before phase 2 has expanded them. `profile: false` disables the profile line
    (-> None). Raises ValueError on a bad `env_sh` shape."""
    layout = runtime_layout(user_name, home, instance_name)
    fmt = (lambda v: _format(v, _SafeScope(scope or {})) if isinstance(v, str) else v)
    nvm = _conf_dict("nvm", nvm, NVM_KEYS)
    pyenv = _conf_dict("pyenv", pyenv, PYENV_KEYS)
    env_sh = _conf_dict("shell_env", env_sh, ENV_SH_KEYS)
    if nvm.get("dir"):
        layout["nvm_dir"] = fmt(nvm["dir"])
    if pyenv.get("root"):
        layout["pyenv_root"] = fmt(pyenv["root"])
    if env_sh.get("path"):
        layout["env_sh"] = fmt(env_sh["path"])
    if "profile" in env_sh:
        profile = env_sh["profile"]
        if profile is False:
            layout["profile"] = None
        elif isinstance(profile, str) and profile:
            layout["profile"] = fmt(profile)
        else:
            raise ValueError("env_sh:profile must be a path string or false, got {!r}".format(profile))
    return layout


def _runtime_path(what, key, path):
    """Absolute, shell-safe path (it is interpolated into double quotes)."""
    if not isinstance(path, str) or not _RUNTIME_PATH_RE.match(path):
        raise ValueError("{}: `{}` must be an absolute path of [A-Za-z0-9_./-] "
                         "characters, got {!r}".format(what, key, path))
    return path.rstrip("/") or "/"


def _runtime_versions(what, versions, version_re):
    if not isinstance(versions, list):
        raise ValueError("{}:versions must be a list of quoted strings like [\"20\"], "
                         "got {!r}".format(what, versions))
    for v in versions:
        if not isinstance(v, str):
            raise ValueError("{}:versions entry {!r} is not a string - quote it "
                             "(YAML 3.10 is the float 3.1, 20 is an int)".format(what, v))
        if not version_re.match(v):
            raise ValueError("{}:versions entry {!r} has characters outside {}".format(
                what, v, version_re.pattern))
    if len(set(versions)) != len(versions):
        raise ValueError("{}:versions has duplicates: {!r}".format(what, versions))
    return list(versions)


def runtime_state_suffix(version):
    """Version -> state-ID-safe suffix ("3.8.13" -> "3_8_13")."""
    return re.sub(r"[^A-Za-z0-9_]", "_", version)


def _runtime_common(what, conf, allowed, layout_key, conf_key, layout, user_name):
    if not conf or not conf.get("versions"):
        _conf_dict(what, conf, allowed)
        return None
    _conf_dict(what, conf, allowed)
    base = _runtime_path(what, conf_key, conf.get(conf_key) or layout[layout_key])
    for key in ("rev", "repo"):
        if not isinstance(conf.get(key), str) or not conf[key]:
            raise ValueError("{}:{} must be a non-empty string, got {!r}".format(what, key, conf.get(key)))
    return base


def _build_pkgs(kind, conf):
    """Validated `<kind>.build_pkgs` list (empty/absent -> [], which skips the
    pkg.installed state)."""
    pkgs = conf.get("build_pkgs") or []
    if not isinstance(pkgs, list) or not all(isinstance(p, str) and p for p in pkgs):
        raise ValueError("{}:build_pkgs must be a list of package names, got {!r}".format(kind, pkgs))
    return list(pkgs)


def nvm_plan(nvm, layout, user_name):
    """Validated nvm plan, or None when `nvm` is absent or has no `versions`
    (defaults.yaml supplies rev/repo only, so defaults stay inert). Keys: dir,
    repo, rev, versions, default (= versions[0]), user (None for root),
    build_pkgs, env, installs [{version, suffix, name, unless}], default_cmd {name, unless}."""
    base = _runtime_common("nvm", nvm, NVM_KEYS, "nvm_dir", "dir", layout, user_name)
    if base is None:
        return None
    versions = _runtime_versions("nvm", nvm["versions"], _NVM_VERSION_RE)
    default = versions[0]
    pkgs = _build_pkgs("nvm", nvm)
    source = '. "{}/nvm.sh"'.format(base)
    installs = []
    for v in versions:
        qv = shlex.quote(v)
        installs.append({
            "version": v,
            "suffix": runtime_state_suffix(v),
            "name": "{} && nvm install {}".format(source, qv),
            "unless": '{} && [ "$(nvm version {})" != "N/A" ]'.format(source, qv),
        })
    return {
        "dir": base,
        "repo": nvm["repo"],
        "rev": nvm["rev"],
        "versions": versions,
        "default": default,
        "user": None if (user_name or "root") == "root" else user_name,
        "build_pkgs": pkgs,
        "env": {"NVM_DIR": base},
        "installs": installs,
        "default_cmd": {
            "name": "{} && nvm alias default {}".format(source, shlex.quote(default)),
            "unless": '[ "$(cat {}/alias/default 2>/dev/null)" = "{}" ]'.format(base, default),
        },
    }


def pyenv_plan(pyenv, layout, user_name):
    """Validated pyenv plan, or None when `pyenv` is absent or has no
    `versions`. Keys: root, repo, rev, versions, default (= versions[0]), user
    (None for root), build_pkgs, env, installs [{version, suffix, name,
    unless}], default_cmd {name, unless}."""
    base = _runtime_common("pyenv", pyenv, PYENV_KEYS, "pyenv_root", "root", layout, user_name)
    if base is None:
        return None
    versions = _runtime_versions("pyenv", pyenv["versions"], _PYENV_VERSION_RE)
    default = versions[0]
    pkgs = _build_pkgs("pyenv", pyenv)
    installs = []
    for v in versions:
        installs.append({
            "version": v,
            "suffix": runtime_state_suffix(v),
            "name": "PYENV_ROOT={r} {r}/bin/pyenv install -s {v}".format(r=base, v=shlex.quote(v)),
            "unless": "test -x {}/versions/{}/bin/python".format(base, v),
        })
    return {
        "root": base,
        "repo": pyenv["repo"],
        "rev": pyenv["rev"],
        "versions": versions,
        "default": default,
        "user": None if (user_name or "root") == "root" else user_name,
        "build_pkgs": pkgs,
        "env": {"PYENV_ROOT": base},
        "installs": installs,
        "default_cmd": {
            "name": "PYENV_ROOT={r} {r}/bin/pyenv global {v}".format(r=base, v=shlex.quote(default)),
            "unless": '[ "$(cat {}/version 2>/dev/null)" = "{}" ]'.format(base, default),
        },
    }


def normalize_tools(tools, layout, user_name, user_group):
    """`tools` keyed map -> ordered [(key, File.managed kwargs)]. Defaults:
    target {tools_dir}/<key>, mode "755" (must be a string), user/group = the
    instance user/group, makedirs true; `source_hash` -> verified download,
    otherwise skip_verify (same choice as fetch's file kind). Raises
    ValueError on a bad key, unknown keys, missing `source`, a non-absolute
    target or a non-string mode."""
    if not tools:
        return []
    if not isinstance(tools, dict):
        raise ValueError("tools must be a keyed map, got {!r}".format(tools))
    result = []
    for key, item in tools.items():
        check_map_key("tools", key)
        if key in (".", ".."):
            raise ValueError("tools: invalid key {!r}".format(key))
        if not isinstance(item, dict):
            raise ValueError("tools:{}: must be a mapping, got {!r}".format(key, item))
        _check_unknown_keys("tools", key, item, TOOL_KEYS)
        source = item.get("source")
        if not isinstance(source, str) or not source:
            raise ValueError("tools:{}: `source` (download URL) is required, got {!r}".format(key, source))
        target = item.get("target") or "{}/{}".format(layout["tools_dir"].rstrip("/"), key)
        if not isinstance(target, str) or not target.startswith("/"):
            raise ValueError("tools:{}: `target` must be an absolute path, got {!r}".format(key, target))
        mode = item.get("mode", "755")
        if not isinstance(mode, str):
            raise ValueError("tools:{}: `mode` must be a quoted string like \"755\", "
                             "got {!r}".format(key, mode))
        kwargs = {"name": target, "source": source, "user": user_name, "group": user_group,
                  "mode": mode, "makedirs": True}
        if item.get("source_hash"):
            kwargs["source_hash"] = item["source_hash"]
        else:
            kwargs["skip_verify"] = True
        result.append((key, kwargs))
    return result


def render_env_sh(plan):
    """Body of the generated env file. `plan`: {name, nvm_dir|None,
    pyenv_root|None, tool_dirs: [dirs]}. Only the sections that apply are
    emitted; tool dirs are de-duplicated in declaration order. Ends with a
    newline."""
    lines = ["# Managed by salt (appsvc instance {}) - do not edit.".format(plan["name"])]
    if plan.get("nvm_dir"):
        lines += ['export NVM_DIR="{}"'.format(plan["nvm_dir"]),
                  '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"']
    if plan.get("pyenv_root"):
        lines += ['export PYENV_ROOT="{}"'.format(plan["pyenv_root"]),
                  'export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"']
    dirs = []
    for d in plan.get("tool_dirs") or []:
        if d not in dirs:
            dirs.append(d)
    if dirs:
        lines.append('export PATH="{}:$PATH"'.format(":".join(dirs)))
    return "\n".join(lines) + "\n"


def runtime_plans(settings):
    """Public wrapper of _runtime_plans: errors name the instance."""
    try:
        return _runtime_plans(settings)
    except ValueError as exc:
        raise ValueError("instance {}: {}".format(settings.get("name"), exc)) from None


def _runtime_plans(settings):
    """Everything the nvm/pyenv/tools/env_sh blocks need, derived from one
    instance's expanded settings: {paths, nvm, pyenv, tools, env_sh}. `nvm` /
    `pyenv` are plans or None, `tools` is the normalize_tools list, `env_sh`
    is None when nothing is active, else {path, body, owner, group, profile,
    profile_line}. Pure; raises ValueError (naming the key) on bad input."""
    user = settings.get("user") or {}
    user_name = user.get("name", "root")
    user_group = user.get("group", user_name)
    name = settings["name"]
    paths = _runtime_paths(user_name, user_home(user), name, settings.get("nvm"),
                           settings.get("pyenv"), settings.get("shell_env"))
    nvm = nvm_plan(settings.get("nvm"), paths, user_name)
    pyenv = pyenv_plan(settings.get("pyenv"), paths, user_name)
    tools = normalize_tools(settings.get("tools"), paths, user_name, user_group)

    env_sh = None
    if nvm or pyenv or tools:
        tool_dirs = [os.path.dirname(kw["name"]) for _, kw in tools]
        path = _runtime_path("shell_env", "path", paths["env_sh"])
        per_user = user_name != "root" and not path.startswith("/etc/")
        profile = paths["profile"]
        env_sh = {
            "path": path,
            "body": render_env_sh({"name": name,
                                   "nvm_dir": nvm["dir"] if nvm else None,
                                   "pyenv_root": pyenv["root"] if pyenv else None,
                                   "tool_dirs": tool_dirs}),
            "owner": user_name if per_user else "root",
            "group": user_group if per_user else "root",
            "profile": _runtime_path("shell_env", "profile", profile) if profile else None,
            "profile_line": '[ -f "{}" ] && . "{}"  # appsvc {}'.format(path, path, name),
        }
    return {"paths": paths, "nvm": nvm, "pyenv": pyenv, "tools": tools, "env_sh": env_sh}
