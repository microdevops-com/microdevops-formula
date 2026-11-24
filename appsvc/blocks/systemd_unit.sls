#!pyobjects
# vim: set ft=python:

from salt://appsvc/lib.py import render_unit

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
    unit_name = systemd.get("unit") or "appsvc_{}".format(prefix[-1])
    unit_path = "/etc/systemd/system/{}.service".format(unit_name)

    sections = {section: systemd[section] for section in ("Unit", "Service", "Install") if systemd.get(section)}

    File.managed(sid + "_unit",
                 name=unit_path,
                 contents=render_unit(sections),
                 user="root", group="root", mode="644")

    # Pre-rename hosts run this instance as binsvc_<name>.service. Without this,
    # the renamed appsvc_<name> unit would start alongside the still-running
    # old one, fail to bind its port, and leave the old process unmanaged.
    # Skipped when the operator pinned the legacy name via systemd.unit.
    # Remove together with init.sls's legacy pillar root (see TODO.md).
    requires = []
    legacy_unit = "binsvc_{}".format(prefix[-1])
    if unit_name != legacy_unit:
        legacy_path = "/etc/systemd/system/{}.service".format(legacy_unit)
        Cmd.run(sid + "_legacy_unit",
                name="systemctl disable --now {0}.service; rm -f {1} && systemctl daemon-reload".format(
                    legacy_unit, legacy_path),
                onlyif="test -e {}".format(legacy_path))
        requires.append(Cmd(sid + "_legacy_unit"))

    onchanges = [File(sid + "_unit")] + list(watch or [])
    Cmd.run(sid + "_restart",
            name="systemctl daemon-reload && systemctl enable {0}.service && systemctl restart {0}.service".format(unit_name),
            onchanges=onchanges,
            require=requires)

    Cmd.run(sid + "_running",
            name="systemctl is-active {0}.service || systemctl start {0}.service".format(unit_name),
            require=requires)

    return [Cmd(sid + "_running")]
