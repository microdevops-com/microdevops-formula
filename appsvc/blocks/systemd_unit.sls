#!pyobjects
# vim: set ft=python:

from salt://appsvc/lib.py import render_unit, systemd_plan

# One system unit per `systemd.units.<unit>` entry (lib.systemd_plan validates
# and resolves names). Presets decide unit content, this block only renders,
# enables and (re)starts - or, for `delete: true`, stops and removes. Units
# dropped from pillar are left alone (not managed); deleting one is explicit.


def systemd_unit(prefix, settings, watch=None):
    """Render /etc/systemd/system/<name>.service for every unit and keep it
    enabled & running; every unit restarts when its file or anything in
    `watch` (the dispatcher's `changed` list) changes. A `delete: true` unit is
    disabled, stopped and its file removed, once. Returns the running-state
    refs of the kept units (for commands(post)), or None when there are none."""

    running = []
    for unit in systemd_plan(settings.get("systemd"), prefix[-1]):
        sid = "_".join(prefix + ["systemd", unit["key"]])
        service = unit["name"] + ".service"

        if unit["delete"]:
            Cmd.run(sid + "_delete",
                    name="systemctl disable --now {0} && rm -f {1} && systemctl daemon-reload"
                         .format(service, unit["path"]),
                    onlyif="test -e {}".format(unit["path"]))
            continue

        File.managed(sid + "_unit",
                     name=unit["path"],
                     contents=render_unit(unit["sections"]),
                     user="root", group="root", mode="644")

        Cmd.run(sid + "_restart",
                name="systemctl daemon-reload && systemctl enable {0} && systemctl restart {0}".format(service),
                onchanges=[File(sid + "_unit")] + list(watch or []))

        Cmd.run(sid + "_running",
                name="systemctl is-active {0} || systemctl start {0}".format(service))
        running.append(Cmd(sid + "_running"))

    return running or None
