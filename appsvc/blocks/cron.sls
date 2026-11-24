#!pyobjects
# vim: set ft=python:

from salt://appsvc/lib.py import normalize_cron


def cron(prefix, settings):
    """Manage crontab entries from `settings["cron"]` (a keyed map). Entries
    are tagged with a Salt `identifier` (appsvc_<instance>_<key>). Removing an
    entry from pillar does NOT remove it from the crontab: set `absent: true`.
    Emits Cron.present / Cron.absent states only; returns nothing."""
    user_name = (settings.get("user") or {}).get("name", "root")
    sid = "_".join(prefix + ["cron"])

    for key, fn, kwargs in normalize_cron(settings.get("cron"), prefix[-1], user_name):
        state_id = sid + "_" + key
        if fn == "present":
            Cron.present(state_id, **kwargs)
        else:
            Cron.absent(state_id, **kwargs)
