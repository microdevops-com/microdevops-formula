from collections import OrderedDict

import pytest

from appsvc_lib.systemd import (
    check_unit_names,
    render_unit,
    systemd_plan,
)


# ── systemd ───────────────────────────────────────────────────────────────────

def test_render_unit_produces_ini_with_repeated_keys_for_lists():
    sections = OrderedDict([
        ("Unit", OrderedDict([("Description", "vlserver vl_main"), ("After", ["network.target", "disk.target"])])),
        ("Service", OrderedDict([("Type", "simple"), ("ExecStart", "/opt/app/bin -arg=1")])),
        ("Install", OrderedDict([("WantedBy", "multi-user.target")])),
    ])
    assert render_unit(sections) == (
        "[Unit]\n"
        "Description=vlserver vl_main\n"
        "After=network.target\n"
        "After=disk.target\n"
        "\n"
        "[Service]\n"
        "Type=simple\n"
        "ExecStart=/opt/app/bin -arg=1\n"
        "\n"
        "[Install]\n"
        "WantedBy=multi-user.target\n"
    )


# ── systemd units ────────────────────────────────────────────────────────────

SD_DEFAULTS = {"name": "appsvc_crm_{unit}",
               "Unit": {"Description": "appsvc: crm ({unit_name})"},
               "Service": {"Type": "simple", "Restart": "on-failure"}}


def _sd(units, **extra):
    return dict({"defaults": SD_DEFAULTS, "units": units}, **extra)


def test_systemd_plan_names_and_merge_with_defaults():
    plan = systemd_plan(_sd({
        "main": {"name": "appsvc_crm", "Service": {"ExecStart": "/bin/main"}},
        "consumer": {"Service": {"ExecStart": "/bin/consume {unit}", "Restart": "always"}},
        "custom": {"name": "crm-worker.service", "Service": {"ExecStart": "/bin/w"}},
    }), "crm")
    assert [(u["key"], u["name"], u["path"]) for u in plan] == [
        ("main", "appsvc_crm", "/etc/systemd/system/appsvc_crm.service"),
        ("consumer", "appsvc_crm_consumer", "/etc/systemd/system/appsvc_crm_consumer.service"),
        ("custom", "crm-worker", "/etc/systemd/system/crm-worker.service")]
    consumer = plan[1]["sections"]
    assert consumer["Unit"] == {"Description": "appsvc: crm (appsvc_crm_consumer)"}
    assert consumer["Service"] == {"Type": "simple", "Restart": "always", "ExecStart": "/bin/consume consumer"}
    assert list(consumer) == ["Unit", "Service"]  # fixed section order, empty ones dropped


def test_systemd_plan_empty_or_unmanaged():
    assert systemd_plan(None, "crm") == []
    assert systemd_plan({"defaults": SD_DEFAULTS}, "crm") == []
    assert systemd_plan(_sd({"main": {}}, manage=False), "crm") == []


def test_systemd_plan_delete_needs_no_execstart():
    [unit] = systemd_plan(_sd({"old": {"delete": True}}), "crm")
    assert unit["delete"] is True and unit["name"] == "appsvc_crm_old"


@pytest.mark.parametrize("units,match", [
    ({"main": {}}, "ExecStart is missing"),
    ({"main": {"Service": {"ExecStart": "  "}}}, "ExecStart is missing"),
    ({"main": {"Service": {"ExecStart": []}}}, "ExecStart is missing"),
    ({"main": {"delete": "yes"}}, "`delete` must be true or false"),
    ({"main": {"bogus": 1, "Service": {"ExecStart": "x"}}}, "unknown key"),
    ({"a b": {"Service": {"ExecStart": "x"}}}, "invalid key"),
    ({"main": {"name": "x.timer", "Service": {"ExecStart": "x"}}}, "only .service"),
    ({"main": {"name": "a/b", "Service": {"ExecStart": "x"}}}, "invalid unit `name`"),
    ({"main": {"name": "app_{nope}", "Service": {"ExecStart": "x"}}}, "unresolved placeholder"),
    ({"main": {"name": "x@1", "Service": {"ExecStart": "x"}}}, "invalid unit `name`"),
    ({"main": {"name": "nginx", "delete": True}}, "distro service"),
    ({"main": {"name": "php8.3-fpm.service", "Service": {"ExecStart": "x"}}}, "distro service"),
    ({"main": {"Service": "x"}}, "Service must be a mapping"),
    ({"a": {"name": "same", "Service": {"ExecStart": "x"}},
      "b": {"name": "same.service", "delete": True}}, "both name unit same.service"),
    (["main"], "keyed map"),
])
def test_systemd_plan_fails_loud(units, match):
    with pytest.raises(ValueError, match=match):
        systemd_plan(_sd(units), "crm")


def test_systemd_plan_rejects_unknown_top_level_and_defaults_keys():
    with pytest.raises(ValueError, match="unknown key"):
        systemd_plan({"units": {}, "Service": {}}, "crm")
    with pytest.raises(ValueError, match="unknown key"):
        systemd_plan({"defaults": {"delete": True}, "units": {}}, "crm")
    with pytest.raises(ValueError, match="`name` must be a non-empty string"):
        systemd_plan({"units": {"main": {"Service": {"ExecStart": "x"}}}}, "crm")


def test_check_unit_names_across_instances():
    unit = lambda key, name: {"key": key, "name": name}
    check_unit_names({"a": [unit("main", "appsvc_a")], "b": [unit("main", "appsvc_b")], "c": []})
    with pytest.raises(ValueError, match=r"consumer.service <- a:consumer, b:worker"):
        check_unit_names({"a": [unit("consumer", "consumer")], "b": [unit("worker", "consumer")]})
