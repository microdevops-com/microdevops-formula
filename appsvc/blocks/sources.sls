#!pyobjects
# vim: set ft=python:

from salt://appsvc/lib.py import git_source_state


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
