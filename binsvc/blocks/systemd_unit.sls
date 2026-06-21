#!pyobjects
# vim: set ft=python:

from salt://binsvc/lib.py import render_unit

# Generalizes exporter/macro.jinja's `service` macro and the systemd-unit half
# of victoriametrics/_setup.sls into a block driven entirely by the merged
# `systemd.{Unit,Service,Install}` settings - presets decide unit content,
# this block only renders, enables and (re)starts it.


def systemd_unit(prefix, settings, watch=None):
    """Render /etc/systemd/system/<unit>.service from settings["systemd"] and
    keep it enabled & running. `watch` is the list of requisite references
    (from a fetch block's return value) that should trigger a restart whenever
    the underlying binary/package changes, in addition to the unit file
    itself."""

    systemd = settings.get("systemd", {})
    sid = "_".join(prefix)
    unit_name = systemd.get("unit") or "binsvc_{}".format(prefix[-1])
    unit_path = "/etc/systemd/system/{}.service".format(unit_name)

    sections = {section: systemd[section] for section in ("Unit", "Service", "Install") if systemd.get(section)}

    File.managed(sid + "_unit",
                 name=unit_path,
                 contents=render_unit(sections),
                 user="root", group="root", mode="644")

    onchanges = [File(sid + "_unit")] + list(watch or [])
    Cmd.run(sid + "_restart",
            name="systemctl daemon-reload && systemctl enable {0}.service && systemctl restart {0}.service".format(unit_name),
            onchanges=onchanges)

    Cmd.run(sid + "_running",
            name="systemctl is-active {0}.service || systemctl start {0}.service".format(unit_name))

    return [Cmd(sid + "_running")]
