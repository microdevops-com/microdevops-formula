#!pyobjects
# vim: set ft=python:

from salt://appsvc/lib.py import runtime_plans

# Built explicitly, not taken from pyobjects' injected globals - see
# blocks/sources.sls for why.
from salt.utils.pyobjects import StateFactory
Git = StateFactory("git")

# `nvm.versions` is a list, not a keyed map: the version set is atomic and
# ordered (the first one is the default alias), so replacing it wholesale on
# merge is the right semantics.


def nvm(prefix, settings):
    """Clone nvm at `rev`, install each version, set the default alias.
    No-op without nvm.versions. Returns refs of the repo, installs and default
    states (they join `changed`)."""
    plan = runtime_plans(settings)["nvm"]
    if not plan:
        return []
    sid = "_".join(prefix + ["nvm"])
    user = {"user": plan["user"]} if plan["user"] else {}
    run = dict(shell="/bin/bash", env=plan["env"], **({"runas": plan["user"]} if plan["user"] else {}))

    Git.latest(sid + "_repo", name=plan["repo"], target=plan["dir"], rev=plan["rev"],
               force_reset=False, **user)
    refs = [Git(sid + "_repo")]

    default_install = None
    for item in plan["installs"]:
        state_id = sid + "_install_" + item["suffix"]
        Cmd.run(state_id, name=item["name"], unless=item["unless"],
                require=[Git(sid + "_repo")], **run)
        refs.append(Cmd(state_id))
        if item["version"] == plan["default"]:
            default_install = Cmd(state_id)

    Cmd.run(sid + "_default", name=plan["default_cmd"]["name"],
            unless=plan["default_cmd"]["unless"], require=[default_install], **run)
    refs.append(Cmd(sid + "_default"))
    return refs
