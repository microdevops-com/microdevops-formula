#!pyobjects
# vim: set ft=python:

from salt://appsvc/lib/app.py import normalize_cron

# Built explicitly, not taken from pyobjects' injected globals: pyobjects only
# injects factories for state modules that load on the *rendering* host, and
# under salt-ssh that is the master/container, which may lack the binary the
# module's __virtual__ needs (crontab -> "name 'Cron' is not defined").
# The target still runs the real state; render no longer depends on the master.
from salt.utils.pyobjects import StateFactory
Cron = StateFactory("cron")


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
