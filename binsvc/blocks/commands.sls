#!pyobjects
# vim: set ft=python:

from salt://binsvc/lib.py import select_commands


def run_commands(prefix, settings, phase, require=None):
    """Emit Cmd.run states for `settings["commands"]` entries in `phase`.

    Commands do not feed the changed/watch restart contract. Use `unless` or
    `onlyif` on entries that must be idempotent. `require` is threaded in by
    dispatch so pre-commands wait for fetch/config, and post-commands wait for
    the service-running state when systemd is managed.
    """
    sid = "_".join(prefix + ["cmd"])
    for name, item in select_commands(settings.get("commands"), phase, settings):
        cmd_id = "{}_{}".format(sid, name)
        kwargs = dict(name=item["cmd"], shell="/bin/bash")
        if require:
            kwargs["require"] = list(require)
        for key in ("cwd", "runas", "unless", "onlyif", "stdin", "env"):
            if key in item:
                kwargs[key] = item[key]
        if "stdin" in item:
            kwargs.setdefault("output_loglevel", item.get("output_loglevel", "quiet"))
        elif "output_loglevel" in item:
            kwargs["output_loglevel"] = item["output_loglevel"]
        Cmd.run(cmd_id, **kwargs)
