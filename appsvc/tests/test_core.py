from collections import OrderedDict

import pytest

from appsvc_lib.core import (
    append_at_path,
    check_map_key,
    collect_scrape_jobs,
    deep_format,
    expand,
    join_args,
    merge,
    merge_args,
    merge_globals,
    parse_filter,
    parse_known_host,
    select_instances,
    user_home,
)


# ── substitute ────────────────────────────────────────────────────────────────

def test_deep_format_recurses_into_nested_structures():
    value = {
        "name": "{instance}-server",
        "args": ["--listen={addr}", "--name={instance}"],
        "nested": {"path": "{install_dir}/bin/{instance}"},
        "untouched": 42,
    }
    result = deep_format(value, {"instance": "vl_main", "addr": "0.0.0.0:9428", "install_dir": "/opt/vl_main"})
    assert result == {
        "name": "vl_main-server",
        "args": ["--listen=0.0.0.0:9428", "--name=vl_main"],
        "nested": {"path": "/opt/vl_main/bin/vl_main"},
        "untouched": 42,
    }
    assert value["name"] == "{instance}-server"  # original untouched


def test_deep_format_leaves_unknown_placeholders_intact():
    result = deep_format({"path": "{install_dir}/{unknown}"}, {"install_dir": "/opt/app"})
    assert result == {"path": "/opt/app/{unknown}"}


def test_expand_resolves_self_references_regardless_of_order():
    mapping = {
        "exec": "{install_dir}/{name} {args}",
        "args": "--config={install_dir}/config.yml",
        "install_dir": "/opt/services/{name}",
        "name": "vlserver",
    }
    result = expand(mapping, scope={"type": "logs"})
    assert result["install_dir"] == "/opt/services/vlserver"
    assert result["args"] == "--config=/opt/services/vlserver/config.yml"
    assert result["exec"] == "/opt/services/vlserver/vlserver --config=/opt/services/vlserver/config.yml"


def test_expand_does_not_mutate_input():
    mapping = {"install_dir": "/opt/{name}", "name": "vl"}
    expand(mapping)
    assert mapping == {"install_dir": "/opt/{name}", "name": "vl"}


def test_expand_resolves_data_dirs_list_through_install_dir():
    # fetch's archive-path svc.data_dirs lean on expand resolving a list of strings
    # that reference {install_dir}, which itself references {name} - so it needs
    # the multi-round self-reference folding, not just a single pass.
    settings = {
        "name": "g1",
        "install_dir": "/opt/services/grafana/{name}",
        "svc": {"data_dirs": ["{install_dir}/data", "{install_dir}/plugins"]},
    }
    result = expand(settings)
    assert result["svc"]["data_dirs"] == [
        "/opt/services/grafana/g1/data",
        "/opt/services/grafana/g1/plugins",
    ]


def test_merge_globals_overlays_operator_placeholders():
    scope = merge_globals(
        {"foo": "bar", "dc": "eu-west"},
        name="vl_main", grain_id="host.example",
    )
    assert scope == {
        "name": "vl_main",
        "grain_id": "host.example",
        "foo": "bar",
        "dc": "eu-west",
    }


def test_merge_globals_tolerates_empty_or_none_globals():
    assert merge_globals({}, name="vl_main") == {"name": "vl_main"}
    assert merge_globals(None, name="vl_main") == {"name": "vl_main"}


def test_merge_globals_does_not_mutate_inputs():
    global_vars = {"foo": "bar"}
    merge_globals(global_vars, name="vl_main")
    assert global_vars == {"foo": "bar"}


def test_merge_globals_fails_loud_on_reserved_collision():
    with pytest.raises(ValueError) as exc:
        merge_globals({"type": "oops", "name": "nope"},
                      name="vl_main", type="vlserver")
    # message names the clashing keys so the typo is obvious
    assert "name" in str(exc.value)
    assert "type" in str(exc.value)


def test_merge_globals_fails_loud_on_phase2_placeholder_collision():
    # a global colliding with a phase-2 name (install_dir/exec/...) would be
    # silently overwritten in the second expand pass, so it must fail loud too.
    with pytest.raises(ValueError) as exc:
        merge_globals({"install_dir": "/oops"}, name="vl_main",
                      extra_reserved=("install_dir", "exec", "args"))
    assert "install_dir" in str(exc.value)


# ── merge ─────────────────────────────────────────────────────────────────────

def test_merge_overrides_scalars_left_to_right():
    assert merge({"version": "v1.0"}, {"version": "v2.0"}, {"version": "v3.0"}) == {"version": "v3.0"}


def test_merge_recurses_into_nested_dicts():
    defaults = {"fetch": {"version_resolver": "github", "tar": {"args": "--strip-components=1"}}, "user": {"name": "root"}}
    preset = {"fetch": {"source": "https://example.com/{name}.tar.gz"}}
    instance = {"fetch": {"version": "v1.9.0"}, "install_dir": "/opt/services/main"}
    result = merge(defaults, preset, instance)
    assert result == {
        "fetch": {
            "version_resolver": "github",
            "tar": {"args": "--strip-components=1"},
            "source": "https://example.com/{name}.tar.gz",
            "version": "v1.9.0",
        },
        "user": {"name": "root"},
        "install_dir": "/opt/services/main",
    }


def test_merge_replaces_lists_wholesale():
    assert merge({"args": ["--a"]}, {"args": ["--b", "--c"]}) == {"args": ["--b", "--c"]}


def test_merge_ignores_falsy_layers():
    assert merge({"a": 1}, {}, None, {"b": 2}) == {"a": 1, "b": 2}


def test_merge_does_not_mutate_inputs():
    defaults = {"fetch": {"tar": {"args": "x"}}}
    instance = {"fetch": {"version": "v1"}}
    result = merge(defaults, instance)
    result["fetch"]["tar"]["args"] = "mutated"
    assert defaults["fetch"]["tar"]["args"] == "x"


# ── scrape collection ────────────────────────────────────────────────────────

def test_collect_scrape_jobs_matches_literal_and_glob_targets():
    instances = OrderedDict([
        ("node", {"scrape": {"vmagent": "metrics", "config": [{"job_name": "node"}]}}),
        ("app", {"scrape": {"vmagent": ["vm-*"], "config": [{"job_name": "app"}]}}),
        ("skip", {"scrape": {"vmagent": ["other"], "config": [{"job_name": "skip"}]}}),
    ])
    assert collect_scrape_jobs(instances, "metrics") == [{"job_name": "node"}]
    assert collect_scrape_jobs(instances, "vm-main") == [{"job_name": "app"}]


def test_collect_scrape_jobs_includes_consumer_own_stanza():
    instances = OrderedDict([
        ("metrics", {"scrape": {"vmagent": ["metrics"], "config": [{"job_name": "vmagent"}]}}),
    ])
    assert collect_scrape_jobs(instances, "metrics") == [{"job_name": "vmagent"}]


def test_collect_scrape_jobs_accepts_scalar_vmagent():
    instances = {"node": {"scrape": {"vmagent": "metrics", "config": [{"job_name": "node"}]}}}
    assert collect_scrape_jobs(instances, "metrics") == [{"job_name": "node"}]


def test_collect_scrape_jobs_requires_vmagent_when_scrape_present():
    with pytest.raises(ValueError, match="'scrape' requires 'vmagent'"):
        collect_scrape_jobs({"bad": {"scrape": {"config": [{"job_name": "bad"}]}}}, "metrics")


def test_collect_scrape_jobs_matching_nothing_is_empty():
    instances = {"node": {"scrape": {"vmagent": ["other"], "config": [{"job_name": "node"}]}}}
    assert collect_scrape_jobs(instances, "metrics") == []


def test_append_at_path_creates_missing_nodes_and_appends():
    container = {}
    result = append_at_path(container, "config:promscrape.yml:contents:scrape_configs", [{"job_name": "node"}])
    assert result == {
        "config": {
            "promscrape.yml": {
                "contents": {
                    "scrape_configs": [{"job_name": "node"}],
                },
            },
        },
    }
    assert result is container


def test_append_at_path_preserves_existing_list_entries():
    container = {"config": {"promscrape.yml": {"contents": {"scrape_configs": [{"job_name": "base"}]}}}}
    append_at_path(container, "config:promscrape.yml:contents:scrape_configs", [{"job_name": "node"}])
    assert container["config"]["promscrape.yml"]["contents"]["scrape_configs"] == [
        {"job_name": "base"},
        {"job_name": "node"},
    ]


def test_append_at_path_unique_key_rejects_duplicates():
    container = {"config": {"promscrape.yml": {"contents": {"scrape_configs": [{"job_name": "node"}]}}}}
    with pytest.raises(ValueError, match="duplicate job_name='node'"):
        append_at_path(
            container,
            "config:promscrape.yml:contents:scrape_configs",
            [{"job_name": "node"}],
            unique_key="job_name",
        )


# ── filter ────────────────────────────────────────────────────────────────────

def test_parse_filter_parses_clauses_and_globs():
    assert parse_filter("name: vm* *gra*; preset: exporter*") == {
        "name": ["vm*", "*gra*"],
        "preset": ["exporter*"],
    }


def test_parse_filter_empty_and_whitespace_mean_no_filter():
    assert parse_filter("") == {}
    assert parse_filter("   ;  ") == {}
    assert parse_filter(None) == {}


def test_parse_filter_repeated_key_unions_globs():
    assert parse_filter("name: vm*; name: *gra*") == {"name": ["vm*", "*gra*"]}


def test_parse_filter_splits_only_on_first_colon():
    # a stray colon in the glob portion must not break parsing
    assert parse_filter("name: a:b *c") == {"name": ["a:b", "*c"]}


def test_parse_filter_rejects_unknown_key():
    with pytest.raises(ValueError, match="unknown"):
        parse_filter("preset: exp*; namee: vm*")


def test_parse_filter_rejects_clause_without_colon():
    with pytest.raises(ValueError, match="not '<key>"):
        parse_filter("vm*")


def test_parse_filter_rejects_key_with_no_globs():
    with pytest.raises(ValueError, match="no globs"):
        parse_filter("name: ; preset: exp*")


def _merged_fixture():
    return OrderedDict([
        ("vm_main", {"preset": "vmserver"}),
        ("vm_logs", {"preset": "vlserver"}),
        ("grafana_eu", {"preset": "grafana"}),
        ("node1", {"preset": "node_exporter"}),
        ("custom", {}),  # preset-less instance
    ])


def test_select_instances_no_filter_selects_all():
    merged = _merged_fixture()
    assert select_instances(merged, {}) == set(merged)


def test_select_instances_by_name_glob():
    assert select_instances(_merged_fixture(), {"name": ["vm_*"]}) == {"vm_main", "vm_logs"}


def test_select_instances_by_preset_glob():
    assert select_instances(_merged_fixture(), {"preset": ["node_*"]}) == {"node1"}


def test_select_instances_unions_name_and_preset():
    selected = select_instances(_merged_fixture(),
                                {"name": ["*gra*"], "preset": ["vmserver"]})
    assert selected == {"grafana_eu", "vm_main"}


def test_select_instances_presetless_only_matched_by_name():
    # 'custom' has no preset, so a preset glob can't reach it; a name glob can
    assert select_instances(_merged_fixture(), {"preset": ["*"]}) == {
        "vm_main", "vm_logs", "grafana_eu", "node1"}
    assert "custom" in select_instances(_merged_fixture(), {"name": ["custom"]})


def test_select_instances_no_match_is_empty():
    assert select_instances(_merged_fixture(), {"name": ["nope*"]}) == set()


def test_join_args_from_mapping():
    assert join_args({"httpListenAddr": "0.0.0.0:8428", "retentionPeriod": 1}) in (
        "-httpListenAddr=0.0.0.0:8428 -retentionPeriod=1",
        "-retentionPeriod=1 -httpListenAddr=0.0.0.0:8428",
    )


def test_join_args_from_ordered_list_preserves_order_and_repeats():
    args = [{"remoteWrite.url": "https://a.example.com/write"}, {"remoteWrite.url": "https://b.example.com/write"}]
    assert join_args(args) == "-remoteWrite.url=https://a.example.com/write -remoteWrite.url=https://b.example.com/write"


def test_join_args_from_ordered_list_keeps_raw_string_tokens():
    args = [{"httpListenAddr": "127.0.0.1:8428"}, "--livereload"]
    assert join_args(args) == "-httpListenAddr=127.0.0.1:8428 --livereload"


def test_join_args_supports_long_flag_prefix():
    assert join_args([{"web.listen-address": "127.0.0.1:9100"}, "--collector.systemd"], "--") == (
        "--web.listen-address=127.0.0.1:9100 --collector.systemd"
    )


def test_join_args_returns_raw_string_unchanged():
    assert join_args("--web.listen-address=127.0.0.1:9100 --collector.systemd") == (
        "--web.listen-address=127.0.0.1:9100 --collector.systemd"
    )


def test_join_args_renders_null_value_as_bare_flag():
    # YAML `- foobar:` / `- baz:` parse to {"foobar": None} / {"baz": None}.
    assert join_args([{"foobar": None}, {"baz": None}], "--") == "--foobar --baz"
    # only an explicit null -> bare flag; "" and 0 keep their =value
    assert join_args([{"a": None}, {"b": ""}, {"c": 0}]) == "-a -b= -c=0"


def test_merge_args_overrides_one_flag_and_keeps_the_rest_in_order():
    preset = [{"httpListenAddr": "127.0.0.1:9428"}, {"storageDataPath": "/data"}, {"retentionPeriod": "1"}]
    instance = [{"httpListenAddr": "127.0.0.1:9429"}]
    assert merge_args(preset, instance) == [
        {"httpListenAddr": "127.0.0.1:9429"},
        {"storageDataPath": "/data"},
        {"retentionPeriod": "1"},
    ]


def test_merge_args_appends_new_flags_in_first_seen_order():
    preset = [{"httpListenAddr": "127.0.0.1:9428"}]
    instance = [{"retentionPeriod": "30d"}, {"httpListenAddr": "127.0.0.1:9429"}]
    assert merge_args(preset, instance) == [
        {"httpListenAddr": "127.0.0.1:9429"},
        {"retentionPeriod": "30d"},
    ]


def test_merge_args_preserves_raw_string_tokens_inside_lists():
    preset = [{"httpListenAddr": "127.0.0.1:9428"}, {"storageDataPath": "/data"}]
    instance = [{"httpListenAddr": "127.0.0.1:9429"}, "--livereload"]
    assert merge_args(preset, instance) == [
        {"httpListenAddr": "127.0.0.1:9429"},
        {"storageDataPath": "/data"},
        "--livereload",
    ]


def test_merge_args_keeps_raw_string_tokens_in_first_seen_order():
    preset = ["--preset-flag", {"httpListenAddr": "127.0.0.1:9428"}]
    instance = [{"retentionPeriod": "30d"}, "--instance-flag"]
    assert merge_args(preset, instance) == [
        "--preset-flag",
        {"httpListenAddr": "127.0.0.1:9428"},
        {"retentionPeriod": "30d"},
        "--instance-flag",
    ]


def test_merge_args_accepts_plain_mapping_layers_too():
    assert merge_args({"httpListenAddr": "127.0.0.1:9428", "retentionPeriod": "1"}, {"retentionPeriod": "30d"}) == [
        {"httpListenAddr": "127.0.0.1:9428"},
        {"retentionPeriod": "30d"},
    ]


def test_merge_args_passes_through_a_single_layer_untouched():
    layer = [{"remoteWrite.url": "https://a.example.com/write"}, {"remoteWrite.url": "https://b.example.com/write"}]
    assert merge_args(None, layer) == layer
    assert merge_args(layer, None) == layer


def test_merge_args_falls_back_to_wholesale_replace_when_a_layer_repeats_a_flag():
    preset = [{"remoteWrite.url": "https://a.example.com/write"}, {"remoteWrite.url": "https://b.example.com/write"}]
    instance = [{"httpListenAddr": "127.0.0.1:9429"}]
    assert merge_args(preset, instance) == instance
    assert merge_args(instance, preset) == preset


def test_merge_args_falls_back_to_wholesale_replace_for_raw_string_layer():
    preset = [{"httpListenAddr": "127.0.0.1:9428"}]
    instance = "-httpListenAddr=127.0.0.1:9429 -retentionPeriod=30d"
    assert merge_args(preset, instance) == instance
    assert merge_args(instance, preset) == preset


def test_merge_args_returns_empty_list_for_no_layers():
    assert merge_args() == []
    assert merge_args(None, None) == []


# ── home ─────────────────────────────────────────────────────────────────────

def test_user_home_root_default_and_empty_user():
    assert user_home({"name": "root"}) == "/root"
    assert user_home({}) == "/root"
    assert user_home(None) == "/root"


def test_user_home_named_user_default():
    assert user_home({"name": "releaser"}) == "/home/releaser"


def test_user_home_explicit_home_wins():
    assert user_home({"name": "releaser", "home": "/var/www/.releaser"}) == "/var/www/.releaser"
    assert user_home({"name": "root", "home": "/srv/root"}) == "/srv/root"


def test_expand_resolves_home_in_install_dir_and_dependent_values():
    # Mirrors init.sls: phase 1 leaves {home} untouched (not in scope yet),
    # phase 2 adds home + install_dir and resolves both chains.
    settings = {"install_dir": "{home}/app", "config": {"p": "{install_dir}/x"},
                "sources": {"b": {"target": "{home}/backend"}}}
    phase1 = expand(settings, {"name": "crm"})
    assert phase1["install_dir"] == "{home}/app"
    scope = {"name": "crm", "install_dir": phase1["install_dir"],
             "home": user_home({"name": "releaser", "home": "/var/www/.releaser"})}
    phase2 = expand(phase1, scope)
    assert phase2["install_dir"] == "/var/www/.releaser/app"
    assert phase2["config"]["p"] == "/var/www/.releaser/app/x"
    assert phase2["sources"]["b"]["target"] == "/var/www/.releaser/backend"


# ── sources ──────────────────────────────────────────────────────────────────

def test_check_map_key_accepts_and_rejects():
    assert check_map_key("x", "back-end_1.v2") == "back-end_1.v2"
    for bad in ("", "a b", "a/b", "a:b", None, 5):
        with pytest.raises(ValueError, match="invalid key"):
            check_map_key("x", bad)


# --- parse_known_host ---------------------------------------------------------

def test_parse_known_host_port_is_int():
    # A string "22" made Salt write "[host]:22", which OpenSSH never matches.
    assert parse_known_host("gitlab.example.com:22") == ("gitlab.example.com", 22, "ssh-ed25519", None)


def test_parse_known_host_defaults_and_full_form():
    assert parse_known_host("example.com") == ("example.com", 22, "ssh-ed25519", None)
    assert parse_known_host("example.com:2222:ssh-rsa") == ("example.com", 2222, "ssh-rsa", None)
    assert parse_known_host("example.com:22:ssh-ed25519:AAAA") == ("example.com", 22, "ssh-ed25519", "AAAA")


@pytest.mark.parametrize("entry", ["", ":22", "h:x", "h:22:e:k:extra"])
def test_parse_known_host_rejects_bad_entries(entry):
    with pytest.raises(ValueError):
        parse_known_host(entry)


def test_env_sh_placeholder_not_shadowed_by_shell_env_settings():
    # The override key is `shell_env`, so an instance that sets it still gets the
    # resolved path for "{env_sh}" (a same-named settings key would be folded into
    # expand's scope and render the dict's repr).
    settings = {"shell_env": {"profile": False}, "cmd": ". {env_sh} && composer install"}
    out = expand(settings, {"env_sh": "/home/helium/.appsvc/crm.sh"})
    assert out["cmd"] == ". /home/helium/.appsvc/crm.sh && composer install"
