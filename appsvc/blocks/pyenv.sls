#!pyobjects
# vim: set ft=python:

from salt://appsvc/lib.py import runtime_plans

# Built explicitly, not taken from pyobjects' injected globals - see
# blocks/sources.sls for why.
from salt.utils.pyobjects import StateFactory
Git = StateFactory("git")

# `pyenv.versions` is a list for the same reason as nvm.versions: atomic and
# ordered (the first one is `pyenv global`).


def pyenv(prefix, settings):
    """Install build packages, clone pyenv at `rev`, build each version, set
    `pyenv global`. No-op without pyenv.versions. Returns refs of the repo,
    installs and global states (they join `changed`)."""
    plan = runtime_plans(settings)["pyenv"]
    if not plan:
        return []
    sid = "_".join(prefix + ["pyenv"])
    user = {"user": plan["user"]} if plan["user"] else {}
    run = dict(shell="/bin/bash", env=plan["env"], **({"runas": plan["user"]} if plan["user"] else {}))

    require = []
    if plan["build_pkgs"]:
        # Guarded like venv's pkgs: pkg.installed rejects an empty pkgs list.
        Pkg.installed(sid + "_build_pkgs", pkgs=plan["build_pkgs"])
        require.append(Pkg(sid + "_build_pkgs"))

    Git.latest(sid + "_repo", name=plan["repo"], target=plan["root"], rev=plan["rev"],
               force_reset=False, require=require, **user)
    refs = [Git(sid + "_repo")]

    default_install = None
    for item in plan["installs"]:
        state_id = sid + "_install_" + item["suffix"]
        Cmd.run(state_id, name=item["name"], unless=item["unless"], timeout=3600,
                require=[Git(sid + "_repo")] + require, **run)
        refs.append(Cmd(state_id))
        if item["version"] == plan["default"]:
            default_install = Cmd(state_id)

    Cmd.run(sid + "_global", name=plan["default_cmd"]["name"],
            unless=plan["default_cmd"]["unless"], require=[default_install], **run)
    refs.append(Cmd(sid + "_global"))
    return refs
