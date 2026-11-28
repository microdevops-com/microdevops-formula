import glob
import os
import re

import pytest
import yaml

from appsvc_lib.core import deep_format, merge
from appsvc_lib.systemd import check_unit_names, systemd_plan
from compat import CHECKS, check_compat, find_problems

ROOT = os.path.join(os.path.dirname(__file__), "..")


def _yaml(path):
    with open(os.path.join(ROOT, path)) as f:
        return yaml.safe_load(f) or {}


def _bundled_presets():
    return {os.path.basename(p)[:-5]: _yaml(p)
            for p in sorted(glob.glob(os.path.join(ROOT, "presets", "*.yaml")))}


def _changelog():
    with open(os.path.join(ROOT, "CHANGELOG.md")) as f:
        return f.read()


# ── the checks themselves ────────────────────────────────────────────────────

@pytest.mark.parametrize("conf,anchor,found", [
    ({"systemd": {"Service": {"ExecStart": "x"}}}, "0.2-systemd-units", ["systemd.Service"]),
    ({"systemd": {"unit": "x", "Unit": {}, "Install": {}}}, "0.2-systemd-units",
     ["systemd.Unit", "systemd.Install", "systemd.unit"]),
    ({"nginx": {"manage": True, "vhost_name": "g", "upstream": "u"}}, "0.1-nginx-vhosts",
     ["nginx.upstream", "nginx.vhost_name"]),
])
def test_old_shape_detected(conf, anchor, found):
    [(path, got, check)] = find_problems({"inst": conf}, None)
    assert path == "appsvc:instances:inst" and got == found and check.anchor == anchor


def test_new_shapes_pass():
    assert find_problems({"a": {"systemd": {"manage": False, "units": {"main": {"Service": {}}}}},
                          "b": {"nginx": {"vhosts": {"w": {"upstream": "u"}}}},
                          "c": {}, "d": None}, {}) == []


def test_pillar_presets_are_checked_and_all_problems_reported_at_once():
    with pytest.raises(ValueError) as err:
        check_compat({"a": {"systemd": {"Service": {}}}, "b": {"nginx": {"servers": []}}},
                     {"mt": {"systemd": {"unit": "x"}}})
    msg = str(err.value)
    assert msg.startswith("appsvc: pillar uses a format that has changed - see appsvc/CHANGELOG.md:")
    assert "appsvc:instances:a: systemd.Service: move" in msg
    assert "[0.2, appsvc/CHANGELOG.md#0.2-systemd-units]" in msg
    assert "appsvc:instances:b: nginx.servers:" in msg
    assert "appsvc:presets:mt: systemd.unit:" in msg


def test_every_check_has_a_changelog_entry():
    changelog = _changelog()
    for check in CHECKS:
        assert '<a id="{}"></a>'.format(check.anchor) in changelog, check.anchor
        assert re.search(r"^## {}$".format(re.escape(check.since)), changelog, re.M), check.since
        assert check.anchor.startswith(check.since + "-")


# ── what we ship is current ──────────────────────────────────────────────────

def test_bundled_presets_and_pillar_example_use_current_shapes():
    example = _yaml("pillar.example")["appsvc"]
    assert find_problems(_bundled_presets(), None) == []
    assert find_problems(example.get("instances"), example.get("presets")) == []


def test_bundled_preset_units_keep_pre_0_2_names():
    # Fleet hosts run appsvc_<instance>.service; a bundled preset renaming its
    # unit would start a second copy next to the old one.
    defaults = _yaml("defaults.yaml")
    for name, preset in _bundled_presets().items():
        settings = deep_format(merge(defaults, preset), {"name": "inst"})
        units = systemd_plan(settings.get("systemd"), "inst") if settings["systemd"].get("manage", True) else []
        for unit in units:
            assert unit["key"] == "main" and unit["name"] == "appsvc_inst", name


def test_pillar_example_units_plan():
    defaults, bundled = _yaml("defaults.yaml"), _bundled_presets()
    example = _yaml("pillar.example")["appsvc"]
    plans = {}
    for name, instance in example["instances"].items():
        preset_name = instance.get("preset")
        preset = merge(bundled.get(preset_name, {}), (example.get("presets") or {}).get(preset_name, {})) \
            if preset_name else {}
        settings = deep_format(merge(defaults, preset, instance), {"name": name})
        plans[name] = systemd_plan(settings.get("systemd"), name)
    check_unit_names(plans)
    assert [u["name"] for u in plans["plain_script"]] == ["appsvc_plain_script_main", "plain-script-report"]
    assert plans["custom_exporter"][0]["name"] == "appsvc_custom_exporter"
    assert plans["crm"] == []
