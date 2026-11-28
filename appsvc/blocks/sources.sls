#!pyobjects
# vim: set ft=python:

from salt://appsvc/lib/app.py import git_source_state

# Built explicitly, not taken from pyobjects' injected globals: pyobjects only
# injects factories for state modules that load on the *rendering* host, and
# under salt-ssh that is the master/container, which may lack the binary the
# module's __virtual__ needs (git -> "name 'Git' is not defined").
# The target still runs the real state; render no longer depends on the master.
from salt.utils.pyobjects import StateFactory
Git = StateFactory("git")


def sources(prefix, settings):
    """Clone/update the git checkouts declared in `settings["sources"]` (a keyed
    map; see presets/generic.yaml). `once: true` -> git.cloned (clone if
    missing, never update); otherwise git.latest.

    Returns {key: Git(<state id>)} - a dict, not a list, because commands'
    `onchanges: [sources:<key>]` needs per-key refs. dispatch also folds the
    values into the `changed` list so a daemon deployed from git restarts when
    its code changes. Returns {} when there are no sources."""
    entries = settings.get("sources") or {}
    sid = "_".join(prefix + ["source"])
    user_name = (settings.get("user") or {}).get("name", "root")

    refs = {}
    for key, source in entries.items():
        fn, kwargs = git_source_state(key, source, user_name)
        state_id = sid + "_" + key
        if fn == "latest":
            Git.latest(state_id, **kwargs)
        else:
            Git.cloned(state_id, **kwargs)
        refs[key] = Git(state_id)
    return refs
