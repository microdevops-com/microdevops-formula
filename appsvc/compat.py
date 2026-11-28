# vim: set ft=python:
"""appsvc compat: detect pillar shapes that a later appsvc version changed.

Runs first in init.sls, on the RAW pillar layers - each appsvc:instances:<name>
and appsvc:presets:<name> - before anything is merged: merging would hide an
old shape under the new defaults, and checking layer by layer names the exact
pillar path. Bundled presets are not checked here; tests/test_compat.py keeps
them clean.

A check only RECOGNISES an old shape and says how to move to the new one, with
a pointer to the CHANGELOG.md entry. It never validates the new shape - that
stays in lib/ next to the code that uses it. Checks are kept indefinitely:
they are cheap, and long-frozen pillar is exactly what they exist for.

No salt or lib imports, so the module is unit-tested with plain pytest.
"""

CHANGELOG = "appsvc/CHANGELOG.md"


class Check:
    """One changed shape. `since`: the appsvc version that changed it;
    `anchor`: the CHANGELOG.md id; `detect(conf)` returns the offending
    settings paths found in one pillar layer (empty when the layer is fine);
    `fix`: a one-line migration hint."""

    def __init__(self, since, anchor, detect, fix):
        self.since, self.anchor, self.detect, self.fix = since, anchor, detect, fix


def _keys_under(section, keys):
    def detect(conf):
        value = conf.get(section)
        if not isinstance(value, dict):
            return []
        return ["{}.{}".format(section, key) for key in keys if key in value]
    return detect


CHECKS = [
    Check("0.1", "0.1-nginx-vhosts",
          _keys_under("nginx", ("upstream", "servers", "vhost_name", "auth_basic")),
          "move the vhost under nginx.vhosts.<key> - nginx: {manage: true, vhosts: {<key>: "
          "{name: <old vhost_name>, upstream: ..., names: [...], acme_account: ...}}}; "
          "`name: <old vhost_name>` keeps the sites-available file and the ACME cert"),
    Check("0.2", "0.2-systemd-units",
          _keys_under("systemd", ("Unit", "Service", "Install", "unit")),
          "move systemd.{Unit,Service,Install} under systemd.units.<unit>; an override of a "
          "bundled preset's unit goes under systemd.units.main; a hand-written unit keeps its "
          "current name with `name: \"appsvc_{name}\"` (was systemd.unit)"),
]


def find_problems(instances, presets, checks=None):
    """[(pillar_path, [settings paths], check)] for every old shape found."""
    problems = []
    for root, layers in (("appsvc:instances", instances), ("appsvc:presets", presets)):
        for name, conf in (layers or {}).items():
            if not isinstance(conf, dict):
                continue
            for check in (CHECKS if checks is None else checks):
                found = check.detect(conf)
                if found:
                    problems.append(("{}:{}".format(root, name), found, check))
    return problems


def format_problems(problems):
    lines = ["appsvc: pillar uses a format that has changed - see {}:".format(CHANGELOG)]
    for path, found, check in problems:
        lines.append("  - {}: {}: {} [{}, {}#{}]".format(
            path, ", ".join(found), check.fix, check.since, CHANGELOG, check.anchor))
    return "\n".join(lines)


def check_compat(instances, presets):
    """Raise ValueError listing every old shape in the pillar, all at once."""
    problems = find_problems(instances, presets)
    if problems:
        raise ValueError(format_problems(problems))
