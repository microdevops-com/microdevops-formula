#!pyobjects
# vim: set ft=python:

from salt://appsvc/lib/app.py import normalize_dirs, check_dirs_outside_sources


def dirs(prefix, settings):
    """Create the writable/working directories in `settings["dirs"]` (a keyed
    map; string shorthand = path). Does not replace `svc.data_dirs`. Raises if a
    dir lies inside a `sources` target. Emits
    File.directory states only; returns nothing."""
    user = settings.get("user") or {}
    user_name = user.get("name", "root")
    user_group = user.get("group", user_name)
    sid = "_".join(prefix + ["dir"])

    entries = normalize_dirs(settings.get("dirs"), user_name, user_group)
    # dirs run before sources: one inside a checkout would block the clone.
    check_dirs_outside_sources(entries, settings.get("sources"))

    for key, kwargs in entries:
        File.directory(sid + "_" + key, **kwargs)
