#!pyobjects
# vim: set ft=python:

from salt://appsvc/lib.py import normalize_dirs


def dirs(prefix, settings):
    """Create the writable/working directories in `settings["dirs"]` (a keyed
    map; string shorthand = path). Does not replace `svc.data_dirs`. Emits
    File.directory states only; returns nothing."""
    user = settings.get("user") or {}
    user_name = user.get("name", "root")
    user_group = user.get("group", user_name)
    sid = "_".join(prefix + ["dir"])

    for key, kwargs in normalize_dirs(settings.get("dirs"), user_name, user_group):
        File.directory(sid + "_" + key, **kwargs)
