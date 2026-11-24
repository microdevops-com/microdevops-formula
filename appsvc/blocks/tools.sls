#!pyobjects
# vim: set ft=python:

from salt://appsvc/lib.py import runtime_plans

# Single-file downloads (composer & co.) from the keyed map `tools`.


def tools(prefix, settings):
    """One File.managed per tool. Returns their refs (they join `changed`);
    [] without tools."""
    sid = "_".join(prefix + ["tool"])
    refs = []
    for key, kwargs in runtime_plans(settings)["tools"]:
        File.managed(sid + "_" + key, **kwargs)
        refs.append(File(sid + "_" + key))
    return refs
