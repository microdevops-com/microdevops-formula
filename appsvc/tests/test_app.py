from collections import OrderedDict
import json

import pytest
import yaml

from appsvc_lib.app import (
    check_dirs_outside_sources,
    cron_identifier,
    cron_schedule_kwargs,
    git_source_state,
    normalize_cron,
    normalize_dirs,
    parse_onchanges,
    render_config,
    resolve_onchanges,
    select_commands,
    sources_containing,
)


# ── commands ─────────────────────────────────────────────────────────────────

def test_select_commands_filters_by_phase_and_defaults_to_post():
    commands = OrderedDict([
        ("setup", {"cmd": "setup", "phase": "pre"}),
        ("api", {"cmd": "api"}),
    ])
    assert select_commands(commands, "pre", {}) == [("setup", commands["setup"])]
    assert select_commands(commands, "post", {}) == [("api", commands["api"])]


def test_select_commands_when_set_skips_missing_or_falsy_and_includes_truthy():
    commands = OrderedDict([
        ("reset", {"cmd": "reset", "when_set": "admin_password"}),
    ])
    assert select_commands(commands, "post", {}) == []
    assert select_commands(commands, "post", {"admin_password": ""}) == []
    assert select_commands(commands, "post", {"admin_password": "secret"}) == [("reset", commands["reset"])]


def test_select_commands_skips_malformed_entries():
    commands = OrderedDict([
        ("bad_scalar", "echo bad"),
        ("bad_missing_cmd", {"phase": "post"}),
        ("good", {"cmd": "echo good"}),
    ])
    assert select_commands(commands, "post", {}) == [("good", commands["good"])]


def test_select_commands_preserves_declaration_order():
    commands = OrderedDict([
        ("first", {"cmd": "1"}),
        ("second", {"cmd": "2"}),
        ("third", {"cmd": "3"}),
    ])
    assert [name for name, _ in select_commands(commands, "post", {})] == ["first", "second", "third"]


# ── config ────────────────────────────────────────────────────────────────────

def test_render_config_yaml_round_trips():
    rendered = render_config({"a": {"b": 1}}, "yaml")
    assert yaml.safe_load(rendered) == {"a": {"b": 1}}


def test_render_config_json_round_trips():
    rendered = render_config({"a": {"b": 1}}, "json")
    assert json.loads(rendered) == {"a": {"b": 1}}
    assert rendered.endswith("\n")


def test_render_config_ini_renders_sections_and_stringifies_values():
    rendered = render_config({"server": {"http_port": 3000}}, "ini")
    assert "[server]" in rendered
    assert "http_port = 3000" in rendered


def test_render_config_ini_preserves_key_case():
    # configparser lowercases option names by default - _render_ini must not.
    rendered = render_config({"section": {"MixedCaseKey": "x"}}, "ini")
    assert "MixedCaseKey = x" in rendered


def test_render_config_ini_allows_percent_in_values():
    # a literal % (e.g. a time format) must not be parsed as interpolation.
    rendered = render_config({"log": {"fmt": "%Y-%m-%d"}}, "ini")
    assert "fmt = %Y-%m-%d" in rendered


def test_render_config_ini_rejects_deeper_nesting():
    with pytest.raises(ValueError):
        render_config({"a": {"b": {"c": 1}}}, "ini")


def test_render_config_ini_rejects_non_mapping():
    with pytest.raises(ValueError):
        render_config(["x"], "ini")


def test_render_config_unknown_format_raises():
    with pytest.raises(ValueError):
        render_config({}, "toml")


def test_render_config_defaults_to_yaml():
    assert render_config({"a": 1}) == render_config({"a": 1}, "yaml")


# ── sources/config/dirs interplay ─────────────────────────────────────────────

SRC = {"back": {"git": "g", "target": "/var/www/app/back"},
       "front": {"git": "g", "target": "/var/www/app/front/"}}


def test_sources_containing_boundaries_and_equal_path():
    assert sources_containing("/var/www/app/back/.env", SRC) == ["back"]
    assert sources_containing("/var/www/app/back", SRC) == ["back"]
    assert sources_containing("/var/www/app/backend/.env", SRC) == []
    assert sources_containing("/var/www/app/front/x/y", SRC) == ["front"]
    assert sources_containing("/var/www/app", SRC) == []


def test_sources_containing_trailing_slash_sorted_and_empty():
    assert sources_containing("/var/www/app/front/", SRC) == ["front"]
    nested = {"z": {"target": "/a"}, "b": {"target": "/a/b"}}
    assert sources_containing("/a/b/c", nested) == ["b", "z"]
    assert sources_containing("/a/b", None) == [] and sources_containing("/a/b", {}) == []


def test_check_dirs_outside_sources_raises_naming_both_keys():
    entries = normalize_dirs({"logs": "/var/www/app/back/var/log"}, "u", "g")
    with pytest.raises(ValueError, match=r"dirs:logs.*sources:back.*onchanges: \[sources:back\]"):
        check_dirs_outside_sources(entries, SRC)
    ok = normalize_dirs({"logs": "/var/www/app/log", "sib": "/var/www/app/backend"}, "u", "g")
    check_dirs_outside_sources(ok, SRC)
    check_dirs_outside_sources(ok, None)


def test_git_source_state_latest_minimal_as_root_omits_user():
    fn, kw = git_source_state("b", {"git": "g@h:r.git", "target": "/srv/b"}, "root")
    assert fn == "latest"
    assert kw == {"name": "g@h:r.git", "target": "/srv/b"}   # force_reset NOT defaulted


def test_git_source_state_latest_passes_only_present_optionals_and_user():
    fn, kw = git_source_state("b", {
        "git": "u", "target": "/srv/b", "branch": "main", "rev": "v1", "identity": "/k",
        "depth": 1, "submodules": True, "force_reset": True, "force_checkout": False,
        "force_clone": True, "force_fetch": False}, "releaser")
    assert fn == "latest"
    assert kw == {"name": "u", "target": "/srv/b", "user": "releaser", "branch": "main",
                  "rev": "v1", "identity": "/k", "depth": 1, "submodules": True,
                  "force_reset": True, "force_checkout": False, "force_clone": True,
                  "force_fetch": False}


def test_git_source_state_once_uses_cloned_with_branch_identity_only():
    fn, kw = git_source_state("b", {"git": "u", "target": "/srv/b", "once": True,
                                    "branch": "m", "identity": "/k"}, "releaser")
    assert fn == "cloned"
    assert kw == {"name": "u", "target": "/srv/b", "user": "releaser", "branch": "m", "identity": "/k"}
    assert "once" not in kw


def test_git_source_state_once_false_is_latest():
    assert git_source_state("b", {"git": "u", "target": "/srv/t", "once": False}, "root")[0] == "latest"


@pytest.mark.parametrize("source,match", [
    ({"target": "/srv/b"}, "git"),
    ({"git": "", "target": "/srv/b"}, "git"),
    ({"git": "u"}, "target"),
    ({"git": "u", "target": "~/b"}, "target"),
    ({"git": "u", "target": "{home}/b"}, "target"),
    ({"git": "u", "target": "rel/b"}, "target"),
    ({"git": "u", "target": "/srv/b", "bogus": 1}, "bogus"),
    ({"git": "u", "target": "/srv/b", "once": True, "rev": "x"}, "rev"),
    ({"git": "u", "target": "/srv/b", "once": True, "force_reset": False}, "force_reset"),
    ({"git": "u", "target": "/srv/b", "once": True, "depth": 1}, "depth"),
    ("not-a-dict", "mapping"),
])
def test_git_source_state_raises_naming_the_problem(source, match):
    with pytest.raises(ValueError, match=match):
        git_source_state("b", source, "root")


def test_git_source_state_error_names_source_key_and_rejects_bad_key():
    with pytest.raises(ValueError, match="sources:backend"):
        git_source_state("backend", {"git": "u"}, "root")
    with pytest.raises(ValueError, match="invalid key"):
        git_source_state("bad key", {"git": "u", "target": "/x"}, "root")


# ── commands: onchanges ──────────────────────────────────────────────────────

def test_parse_onchanges_key_and_whole_block():
    assert parse_onchanges(["sources:backend", "sources"]) == [("sources", "backend"), ("sources", None)]


@pytest.mark.parametrize("spec,match", [
    ("sources:backend", "must be a list"),
    (None, "must be a list"),
    ([], "empty"),
    (["dirs:x"], "unknown block.*sources"),
    (["nonsense"], "unknown block"),
    (["sources:"], "empty key"),
    ([5], "string"),
])
def test_parse_onchanges_raises(spec, match):
    with pytest.raises(ValueError, match=match):
        parse_onchanges(spec)


def test_resolve_onchanges_per_key_and_all():
    refs = {"sources": {"a": "REF_A", "b": "REF_B"}}
    assert resolve_onchanges("c", ["sources:b"], refs) == ["REF_B"]
    assert resolve_onchanges("c", ["sources"], refs) == ["REF_A", "REF_B"]
    assert resolve_onchanges("c", ["sources:a", "sources"], refs) == ["REF_A", "REF_B"]


def test_resolve_onchanges_unknown_key_and_empty_resolution_raise():
    with pytest.raises(ValueError, match="sources:nope"):
        resolve_onchanges("c", ["sources:nope"], {"sources": {"a": "R"}})
    with pytest.raises(ValueError, match="never run"):
        resolve_onchanges("c", ["sources"], {"sources": {}})
    with pytest.raises(ValueError, match="never run"):
        resolve_onchanges("c", ["sources"], None)


def test_resolve_onchanges_on_skipped_block_means_skip_the_command():
    # appsvc:filter block: without sources - the source states are not in the
    # run, so they cannot change; still validated (a typo still fails).
    assert resolve_onchanges("c", ["sources:back"], {"sources": {}}, skipped={"sources"}) is None
    with pytest.raises(ValueError, match="unknown block"):
        resolve_onchanges("c", ["sourcez:back"], {}, skipped={"sources"})


def test_select_commands_keeps_onchanges_entries_in_order():
    commands = OrderedDict([
        ("a", {"cmd": "a", "phase": "pre", "onchanges": ["sources:x"]}),
        ("b", {"cmd": "b", "phase": "pre"}),
        ("c", {"cmd": "c", "phase": "pre", "onchanges": ["sources"]}),
    ])
    assert [n for n, _ in select_commands(commands, "pre", {})] == ["a", "b", "c"]
    assert select_commands(commands, "pre", {})[0][1]["onchanges"] == ["sources:x"]


# ── dirs ─────────────────────────────────────────────────────────────────────

def test_normalize_dirs_string_shorthand_and_defaults():
    assert normalize_dirs({"s": "/var/lib/s"}, "u", "g") == [
        ("s", {"name": "/var/lib/s", "user": "u", "group": "g", "mode": "755", "makedirs": True})]


def test_normalize_dirs_full_entry_and_recurse_and_order():
    result = normalize_dirs(OrderedDict([
        ("z", "/z"),
        ("logs", {"name": "/l", "user": "x", "group": "y", "mode": "750",
                  "makedirs": False, "recurse": True}),
    ]), "u", "g")
    assert [k for k, _ in result] == ["z", "logs"]
    assert result[1][1] == {"name": "/l", "user": "x", "group": "y", "mode": "750",
                            "makedirs": False, "recurse": ["user", "group"]}


def test_normalize_dirs_empty_is_empty_list():
    assert normalize_dirs(None, "u", "g") == []
    assert normalize_dirs({}, "u", "g") == []


@pytest.mark.parametrize("dirs,match", [
    ({"bad key": "/x"}, "invalid key"),
    ({"a": "rel/x"}, "absolute"),
    ({"a": "~/x"}, "absolute"),
    ({"a": {"mode": "750"}}, "absolute"),
    ({"a": {"name": "/x", "owner": "u"}}, "owner"),
    ({"a": {"name": "/x", "mode": 750}}, "mode"),
    ({"a": 5}, "path string or a mapping"),
    (["/x"], "keyed map"),
])
def test_normalize_dirs_raises(dirs, match):
    with pytest.raises(ValueError, match=match):
        normalize_dirs(dirs, "u", "g")


# ── cron ─────────────────────────────────────────────────────────────────────

def test_cron_identifier():
    assert cron_identifier("crm", "session_clean") == "appsvc_crm_session_clean"


def test_cron_schedule_kwargs_five_fields_and_special():
    assert cron_schedule_kwargs("0 * * * *") == {
        "minute": "0", "hour": "*", "daymonth": "*", "month": "*", "dayweek": "*"}
    assert cron_schedule_kwargs("*/5  1-3 * * 1,2") == {
        "minute": "*/5", "hour": "1-3", "daymonth": "*", "month": "*", "dayweek": "1,2"}
    assert cron_schedule_kwargs("@daily") == {"special": "@daily"}
    assert cron_schedule_kwargs("@reboot") == {"special": "@reboot"}


@pytest.mark.parametrize("schedule", ["daily", "* * * *", "* * * * * *", "", "@bogus", "@daily x", None])
def test_cron_schedule_kwargs_raises(schedule):
    with pytest.raises(ValueError, match="cron schedule"):
        cron_schedule_kwargs(schedule)


def test_normalize_cron_present_defaults_and_options():
    result = normalize_cron(OrderedDict([
        ("clean", {"schedule": "0 * * * *", "cmd": "find x", "user": "root"}),
        ("job", {"schedule": "@daily", "cmd": "run", "comment": "hi", "disabled": True}),
    ]), "crm", "releaser")
    assert [(k, f) for k, f, _ in result] == [("clean", "present"), ("job", "present")]
    assert result[0][2] == {"name": "find x", "user": "root", "identifier": "appsvc_crm_clean",
                            "minute": "0", "hour": "*", "daymonth": "*", "month": "*", "dayweek": "*"}
    assert result[1][2] == {"name": "run", "user": "releaser", "identifier": "appsvc_crm_job",
                            "special": "@daily", "comment": "hi", "commented": True}


def test_normalize_cron_absent_needs_no_cmd_or_schedule():
    result = normalize_cron({"old": {"absent": True}, "old2": {"absent": True, "cmd": "x"}}, "crm", "u")
    assert result == [
        ("old", "absent", {"user": "u", "identifier": "appsvc_crm_old"}),
        ("old2", "absent", {"user": "u", "identifier": "appsvc_crm_old2", "name": "x"})]


@pytest.mark.parametrize("cron,match", [
    ({"a": {"schedule": "@daily"}}, "cmd"),
    ({"a": {"cmd": "x"}}, "schedule"),
    ({"a": {"cmd": "x", "schedule": "@daily", "when": 1}}, "when"),
    ({"a": {"cmd": "x", "schedule": "nope"}}, "cron schedule"),
    ({"bad key": {"cmd": "x", "schedule": "@daily"}}, "invalid key"),
    ({"a": "x"}, "mapping"),
    (["x"], "keyed map"),
])
def test_normalize_cron_raises(cron, match):
    with pytest.raises(ValueError, match=match):
        normalize_cron(cron, "crm", "u")


def test_normalize_cron_empty():
    assert normalize_cron(None, "crm", "u") == []
