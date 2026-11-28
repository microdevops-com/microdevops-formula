import json
import os
import sys
from collections import OrderedDict
from unittest.mock import MagicMock, patch

import pytest
import yaml

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from lib import (
    logrotate_plan,
    render_logrotate,
    php_reopen_command,
    parse_known_host,
    deep_format, expand, merge_globals,
    merge,
    normalize_osarch, archive_path, tar_extract_command,
    source_basename, fetch_kind, fetch_target,
    venv_requirement_paths, venv_digest_command, venv_guard_command, venv_build_command,
    VENV_INLINE_REQUIREMENTS_NAME, VENV_STAMP_NAME,
    repo_from_source, repo_url, latest_from_release, resolve_latest,
    GITHUB_RELEASES_URL, GITHUB_RELEASES_LIST_URL, GRAFANA_VERSIONS_URL, GRAFANA_PACKAGES_URL,
    cached_get_json, _cache_path,
    select_commands,
    collect_scrape_jobs, append_at_path,
    parse_filter, select_instances,
    render_config, render_unit, merge_args, join_args,
    acme_cert_paths, normalize_nginx_vhosts, nginx_template_context,
    sources_containing, check_dirs_outside_sources,
    normalize_php_pools, render_php_pool, php_reload_command,
    user_home, check_map_key, git_source_state, parse_onchanges, resolve_onchanges,
    normalize_dirs, cron_identifier, cron_schedule_kwargs, normalize_cron,
    systemd_plan, check_unit_names,
    runtime_layout, runtime_paths, nvm_plan, pyenv_plan, normalize_tools, render_env_sh,
    runtime_plans, runtime_state_suffix,
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


# ── fetch ─────────────────────────────────────────────────────────────────────

def test_normalize_osarch_maps_known_aliases_and_passes_through_others():
    assert normalize_osarch("x86_64") == "amd64"
    assert normalize_osarch("aarch64") == "arm64"
    assert normalize_osarch("amd64") == "amd64"


def test_archive_path_joins_cache_dir_kind_and_url_basename():
    source = "https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v1.101.0/victoria-metrics-linux-amd64-v1.101.0.tar.gz"
    assert archive_path("/var/cache/salt/appsvc/", "vmserver", source) == (
        "/var/cache/salt/appsvc/vmserver/victoria-metrics-linux-amd64-v1.101.0.tar.gz"
    )


def test_tar_extract_command_includes_optional_args_and_unpack():
    assert tar_extract_command("/cache/a.tar.gz", "/opt/app") == (
        "tar --no-same-owner --directory /opt/app --extract --file /cache/a.tar.gz"
    )
    assert tar_extract_command("/cache/a.tar.gz", "/opt/app", args="--strip-components=1", unpack="binary") == (
        "tar --strip-components=1 --no-same-owner --directory /opt/app --extract --file /cache/a.tar.gz binary"
    )


# ── fetch kind/target ────────────────────────────────────────────────────────

def test_source_basename_strips_query_and_fragment():
    assert source_basename("https://x/y/app.tar.gz?token=1") == "app.tar.gz"
    assert source_basename("https://x/y/app.tar.gz#frag") == "app.tar.gz"
    assert source_basename("salt://my-formula/files/script.py") == "script.py"


def test_fetch_kind_recognizes_archive_suffixes():
    for suffix in (".tar.gz", ".tgz", ".tar"):
        assert fetch_kind({"source": "https://x/app" + suffix}) == "archive"


def test_fetch_kind_defaults_to_file_for_scripts_and_extensionless_and_randomized_names():
    assert fetch_kind({"source": "https://x/redis_check.py"}) == "file"
    assert fetch_kind({"source": "https://x/my_binary"}) == "file"
    assert fetch_kind({"source": "https://x/redis_check.kgqGOxiz.py"}) == "file"


def test_fetch_kind_explicit_kind_wins_over_tar_and_suffix():
    assert fetch_kind({"kind": "file", "tar": {}, "source": "https://x/app.tar.gz"}) == "file"
    assert fetch_kind({"kind": "archive", "source": "https://x/script.py"}) == "archive"


def test_fetch_kind_invalid_explicit_kind_raises():
    with pytest.raises(ValueError, match="svc.kind"):
        fetch_kind({"kind": "zip"})


def test_fetch_kind_tar_present_wins_over_non_archive_suffix():
    assert fetch_kind({"tar": {}, "source": "https://x/redis_check.py"}) == "archive"


def test_fetch_kind_unsupported_suffix_raises_naming_it():
    with pytest.raises(ValueError, match=r"\.zip"):
        fetch_kind({"source": "https://x/app.zip"})


def test_fetch_kind_bare_gz_raises_but_tar_gz_does_not():
    with pytest.raises(ValueError, match=r"\.gz"):
        fetch_kind({"source": "https://x/app.gz"})
    assert fetch_kind({"source": "https://x/app.tar.gz"}) == "archive"


def test_fetch_kind_query_string_stripped_before_suffix_check():
    assert fetch_kind({"source": "https://x/y/app.tar.gz?token=1"}) == "archive"


def test_fetch_target_defaults_to_install_dir_plus_basename():
    svc = {"source": "https://x/y/redis_check.py?token=1"}
    assert fetch_target(svc, "/opt/services/redis_check/main") == (
        "/opt/services/redis_check/main/redis_check.py"
    )


def test_fetch_target_uses_explicit_target():
    svc = {"source": "https://x/y/redis_check.py", "target": "/opt/app/bin/redis_check.py"}
    assert fetch_target(svc, "/opt/app") == "/opt/app/bin/redis_check.py"


def test_fetch_target_raises_on_empty_source():
    with pytest.raises(ValueError, match="svc.source is empty"):
        fetch_target({}, "/opt/app")


# ── venv ──────────────────────────────────────────────────────────────────────

def test_venv_requirement_paths_inline_only():
    paths = venv_requirement_paths({"requirements": ["redis>=4.2"]}, "/opt/services/redis_check")
    assert paths == ["/opt/services/redis_check/" + VENV_INLINE_REQUIREMENTS_NAME]


def test_venv_requirement_paths_files_only():
    paths = venv_requirement_paths({"requirements_files": ["/opt/app/requirements.txt"]}, "/opt/app")
    assert paths == ["/opt/app/requirements.txt"]


def test_venv_requirement_paths_inline_before_files():
    paths = venv_requirement_paths(
        {"requirements": ["redis>=4.2"], "requirements_files": ["/opt/app/requirements.txt"]},
        "/opt/app")
    assert paths == [
        "/opt/app/" + VENV_INLINE_REQUIREMENTS_NAME,
        "/opt/app/requirements.txt",
    ]


def test_venv_requirement_paths_raises_when_both_empty():
    with pytest.raises(ValueError, match="nothing to install"):
        venv_requirement_paths({}, "/opt/app")


def test_venv_requirement_paths_strips_trailing_slash_on_install_dir():
    paths = venv_requirement_paths({"requirements": ["redis>=4.2"]}, "/opt/app/")
    assert paths == ["/opt/app/" + VENV_INLINE_REQUIREMENTS_NAME]


def test_venv_digest_command_contains_all_paths_in_order():
    command = venv_digest_command(["/opt/app/a.txt", "/opt/app/b.txt"], "python3", "")
    assert "cat /opt/app/a.txt /opt/app/b.txt" in command
    assert command.index("a.txt") < command.index("b.txt")
    assert command.strip().endswith("sha256sum | cut -d' ' -f1")


def test_venv_digest_command_includes_python_version_and_pip_args():
    command = venv_digest_command(["/opt/app/a.txt"], "python3.11", "--no-cache-dir")
    assert "python3.11 -V" in command
    assert "'--no-cache-dir'" in command


def test_venv_guard_command_is_a_single_shell_command():
    # ONE command chained with && - not a list. Salt's `unless` treats a list
    # as all-must-pass; a hand-rolled list here would silently change semantics.
    venv_conf = {"dir": "/opt/app/venv", "python": "python3"}
    guard = venv_guard_command(venv_conf, ["/opt/app/reqs.txt"], "/opt/app/venv/" + VENV_STAMP_NAME)
    assert isinstance(guard, str)
    assert "\n" not in guard
    assert guard.count("&&") == 2


def test_venv_guard_command_checks_venv_interpreter_and_stamp():
    venv_conf = {"dir": "/opt/app/venv", "python": "python3.11"}
    guard = venv_guard_command(venv_conf, ["/opt/app/reqs.txt"], "/opt/app/venv/stamp")
    assert "[ -x /opt/app/venv/bin/python ]" in guard
    assert "/opt/app/venv/bin/python -V" in guard
    assert "python3.11 -V" in guard
    assert "cat /opt/app/venv/stamp" in guard


def test_venv_build_command_recreate_on_change_true_always_clears():
    venv_conf = {"dir": "/opt/app/venv", "python": "python3", "recreate_on_change": True}
    build = venv_build_command(venv_conf, ["/opt/app/reqs.txt"], "/opt/app/venv/stamp")
    lines = build.splitlines()
    assert lines[0] == "set -eu"
    assert lines[1] == "python3 -m venv --clear /opt/app/venv"


def test_venv_build_command_recreate_on_change_false_guards_the_create_line():
    venv_conf = {"dir": "/opt/app/venv", "python": "python3", "recreate_on_change": False}
    build = venv_build_command(venv_conf, ["/opt/app/reqs.txt"], "/opt/app/venv/stamp")
    create_line = build.splitlines()[1]
    assert "--clear" not in create_line
    assert "[ -x /opt/app/venv/bin/python ]" in create_line
    assert create_line.endswith("|| python3 -m venv /opt/app/venv")


def test_venv_build_command_upgrade_pip_adds_a_line():
    venv_conf = {"dir": "/opt/app/venv", "python": "python3", "upgrade_pip": True}
    build = venv_build_command(venv_conf, ["/opt/app/reqs.txt"], "/opt/app/venv/stamp")
    assert "/opt/app/venv/bin/pip install --require-virtualenv -U pip" in build


def test_venv_build_command_upgrade_pip_default_omits_the_line():
    venv_conf = {"dir": "/opt/app/venv", "python": "python3"}
    build = venv_build_command(venv_conf, ["/opt/app/reqs.txt"], "/opt/app/venv/stamp")
    assert "-U pip" not in build


def test_venv_build_command_installs_every_requirement_path():
    venv_conf = {"dir": "/opt/app/venv", "python": "python3"}
    build = venv_build_command(venv_conf, ["/opt/app/a.txt", "/opt/app/b.txt"], "/opt/app/venv/stamp")
    assert "-r /opt/app/a.txt -r /opt/app/b.txt" in build


def test_venv_build_command_pip_args_reach_the_install_line_and_the_digest():
    venv_conf = {"dir": "/opt/app/venv", "python": "python3", "pip_args": "--no-cache-dir"}
    build = venv_build_command(venv_conf, ["/opt/app/reqs.txt"], "/opt/app/venv/stamp")
    assert "pip install --require-virtualenv --no-cache-dir -r /opt/app/reqs.txt" in build
    assert "'--no-cache-dir'" in build  # the digest line


def test_venv_build_command_stamps_last_and_only_after_a_successful_install():
    venv_conf = {"dir": "/opt/app/venv", "python": "python3"}
    build = venv_build_command(venv_conf, ["/opt/app/reqs.txt"], "/opt/app/venv/stamp")
    lines = build.splitlines()
    assert lines[-1].endswith("> /opt/app/venv/stamp")
    install_idx = next(i for i, line in enumerate(lines) if "pip install --require-virtualenv" in line)
    assert install_idx < len(lines) - 1


# ── release ───────────────────────────────────────────────────────────────────

def test_repo_from_source_extracts_owner_repo_from_release_url():
    source = "https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/{tag}/vmutils-linux-{osarch}-{tag}.tar.gz"
    assert repo_from_source(source) == "VictoriaMetrics/VictoriaMetrics"


def test_repo_url_fills_repo_placeholder():
    template = "https://api.github.com/repos/{repo}/releases/latest"
    source = "https://github.com/prometheus/node_exporter/releases/download/{tag}/node_exporter-{tag}.tar.gz"
    assert repo_url(template, source) == "https://api.github.com/repos/prometheus/node_exporter/releases/latest"


def test_latest_from_release_strips_known_suffixes():
    assert latest_from_release({"tag_name": "v1.101.0-cluster"}) == "v1.101.0"
    assert latest_from_release({"tag_name": "v1.101.0"}) == "v1.101.0"


def test_resolve_latest_returns_unchanged_when_version_is_already_concrete():
    svc = {"version_resolver": "github", "version": "v1.9.0", "source": "https://github.com/owner/repo/releases/..."}
    assert resolve_latest(svc, "github") is svc


def test_resolve_latest_returns_unchanged_when_no_source():
    svc = {"version_resolver": "github", "version": "latest"}
    assert resolve_latest(svc, "github") is svc


def test_resolve_latest_fetches_and_resolves_tag():
    svc = {
        "version_resolver": "github",
        "version": "latest",
        "source": "https://github.com/VictoriaMetrics/VictoriaLogs/releases/download/{tag}/victoria-logs-linux-amd64-{tag}.tar.gz",
    }
    mock_response = MagicMock()
    mock_response.json.return_value = {"tag_name": "v1.50.0"}

    with patch("lib.requests.get", return_value=mock_response) as mock_get:
        result = resolve_latest(svc, "github")

    mock_get.assert_called_once_with("https://api.github.com/repos/VictoriaMetrics/VictoriaLogs/releases/latest", timeout=10)
    mock_response.raise_for_status.assert_called_once()
    assert result["version"] == "v1.50.0"
    assert result["tag"] == "v1.50.0"
    assert result["source"] == svc["source"]


def test_resolve_latest_strips_cluster_suffix():
    svc = {
        "version_resolver": "github",
        "version": "latest",
        "source": "https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/{tag}/victoria-metrics-linux-amd64-{tag}.tar.gz",
    }
    mock_response = MagicMock()
    mock_response.json.return_value = {"tag_name": "v1.101.0-cluster"}
    with patch("lib.requests.get", return_value=mock_response) as mock_get:
        result = resolve_latest(svc, "github")
    mock_get.assert_called_once_with("https://api.github.com/repos/VictoriaMetrics/VictoriaMetrics/releases/latest", timeout=10)
    assert result["version"] == "v1.101.0"
    assert result["tag"] == "v1.101.0"


def test_resolve_latest_github_versionsort_picks_highest_version_release():
    svc = {
        "version_resolver": "github_versionsort",
        "version": "latest",
        "source": "https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/{tag}/victoria-metrics-linux-amd64-{tag}.tar.gz",
    }
    resp = MagicMock()
    resp.json.return_value = [
        {"tag_name": "v1.136.11"},
        {"tag_name": "v1.145.0"},
        {"tag_name": "v1.144.0"},
    ]

    with patch("lib.requests.get", return_value=resp) as mock_get:
        result = resolve_latest(svc, "github_versionsort")

    mock_get.assert_called_once_with(
        GITHUB_RELEASES_LIST_URL.format(repo="VictoriaMetrics/VictoriaMetrics", page=1),
        timeout=10,
    )
    assert result["version"] == "v1.145.0"
    assert result["tag"] == "v1.145.0"


def test_resolve_latest_github_versionsort_strips_cluster_suffix_and_ignores_prerelease():
    svc = {
        "version_resolver": "github_versionsort",
        "version": "latest",
        "source": "https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/{tag}/victoria-metrics-linux-amd64-{tag}.tar.gz",
    }
    resp = MagicMock()
    resp.json.return_value = [
        {"tag_name": "v1.145.1-rc1", "prerelease": True},
        {"tag_name": "v1.144.0-cluster"},
        {"tag_name": "v1.143.0", "draft": True},
    ]

    with patch("lib.requests.get", return_value=resp):
        result = resolve_latest(svc, "github_versionsort")

    assert result["version"] == "v1.144.0"
    assert result["tag"] == "v1.144.0"


def test_resolve_latest_github_versionsort_follows_release_pages():
    svc = {
        "version_resolver": "github_versionsort",
        "version": "latest",
        "source": "https://github.com/owner/repo/releases/download/{tag}/app-{tag}.tar.gz",
    }
    page1 = MagicMock()
    page1.json.return_value = [{"tag_name": "v1.{}.0".format(index)} for index in range(100)]
    page2 = MagicMock()
    page2.json.return_value = [{"tag_name": "v1.100.0"}]

    with patch("lib.requests.get", side_effect=[page1, page2]) as mock_get:
        result = resolve_latest(svc, "github_versionsort")

    assert [call.args[0] for call in mock_get.call_args_list] == [
        GITHUB_RELEASES_LIST_URL.format(repo="owner/repo", page=1),
        GITHUB_RELEASES_LIST_URL.format(repo="owner/repo", page=2),
    ]
    assert result["version"] == "v1.100.0"


def test_github_versionsort_resolver_sends_bearer_token_when_configured():
    svc = {
        "version_resolver": "github_versionsort",
        "version": "latest",
        "source": "https://github.com/owner/repo/releases/download/{tag}/app-{tag}.tar.gz",
    }
    resp = MagicMock()
    resp.json.return_value = [{"tag_name": "v9.9.9"}]
    with patch("lib.requests.get", return_value=resp) as mock_get:
        result = resolve_latest(svc, "github_versionsort", {"github_token": "secret-token"})
    assert mock_get.call_args.kwargs["headers"] == {"Authorization": "Bearer secret-token"}
    assert result["version"] == "v9.9.9"


def test_resolve_latest_grafana_picks_latest_stable_and_linux_package():
    svc = {"version_resolver": "grafana", "version": "latest"}
    versions_response = MagicMock()
    versions_response.json.return_value = {
        "items": [
            {"version": "13.1.0-27729613434", "channels": {"nightly": True, "stable": False}},
            {"version": "13.0.2", "channels": {"stable": True}},
        ]
    }
    packages_response = MagicMock()
    packages_response.json.return_value = {
        "items": [
            {
                "version": "13.0.2",
                "os": "linux",
                "arch": "arm64",
                "url": "https://example.com/grafana_13.0.2_linux_arm64.tar.gz",
            },
            {
                "version": "13.0.2",
                "os": "linux",
                "arch": "amd64",
                "url": "https://example.com/grafana_13.0.2_linux_amd64.tar.gz",
                "sha256": "abc123",
                "links": [
                    {"rel": "self", "href": "/self"},
                    {"rel": "download", "href": "https://download.example.com/grafana_13.0.2_linux_amd64.tar.gz"},
                ],
            },
        ]
    }

    with patch("lib.requests.get", side_effect=[versions_response, packages_response]) as mock_get:
        result = resolve_latest(svc, "grafana", {"osarch": "amd64"})

    assert mock_get.call_args_list[0].args == (GRAFANA_VERSIONS_URL,)
    assert mock_get.call_args_list[0].kwargs == {"timeout": 10}
    assert mock_get.call_args_list[1].args == (GRAFANA_PACKAGES_URL.format(version="13.0.2"),)
    assert mock_get.call_args_list[1].kwargs == {"timeout": 10}
    assert result["version"] == "13.0.2"
    assert result["tag"] == "13.0.2"
    assert result["source"] == "https://download.example.com/grafana_13.0.2_linux_amd64.tar.gz"
    assert result["source_hash"] == "sha256=abc123"


def test_resolve_latest_grafana_resolves_concrete_version_package_without_source():
    svc = {"version_resolver": "grafana", "version": "13.0.1"}
    packages_response = MagicMock()
    packages_response.json.return_value = {
        "items": [
            {
                "version": "13.0.1",
                "os": "linux",
                "arch": "amd64",
                "url": "https://example.com/grafana_13.0.1_linux_amd64.tar.gz",
            },
        ]
    }

    with patch("lib.requests.get", return_value=packages_response) as mock_get:
        result = resolve_latest(svc, "grafana", {"osarch": "amd64"})

    mock_get.assert_called_once_with(GRAFANA_PACKAGES_URL.format(version="13.0.1"), timeout=10)
    assert result["version"] == "13.0.1"
    assert result["tag"] == "13.0.1"
    assert result["source"] == "https://example.com/grafana_13.0.1_linux_amd64.tar.gz"


def test_github_resolver_sends_bearer_token_when_configured():
    svc = {
        "version_resolver": "github",
        "version": "latest",
        "source": "https://github.com/owner/repo/releases/download/{tag}/app-{tag}.tar.gz",
    }
    resp = MagicMock()
    resp.json.return_value = {"tag_name": "v9.9.9"}
    with patch("lib.requests.get", return_value=resp) as mock_get:
        result = resolve_latest(svc, "github", {"github_token": "secret-token"})
    assert mock_get.call_args.kwargs["headers"] == {"Authorization": "Bearer secret-token"}
    assert result["version"] == "v9.9.9"


def test_github_resolver_sends_no_auth_header_without_token():
    svc = {
        "version_resolver": "github",
        "version": "latest",
        "source": "https://github.com/owner/repo/releases/download/{tag}/app-{tag}.tar.gz",
    }
    resp = MagicMock()
    resp.json.return_value = {"tag_name": "v9.9.9"}
    with patch("lib.requests.get", return_value=resp) as mock_get:
        resolve_latest(svc, "github", {})
    assert "headers" not in mock_get.call_args.kwargs


def test_resolve_latest_unknown_resolver_raises():
    svc = {"version": "latest", "source": "https://example.com/app.tar.gz"}
    try:
        resolve_latest(svc, "unknown")
    except ValueError as exc:
        assert "unknown version_resolver" in str(exc)
    else:
        raise AssertionError("expected ValueError")


# ── resolve cache ───────────────────────────────────────────────────────────────

def _age_cache_entry(cache_dir, url, by_seconds):
    path = _cache_path(cache_dir, url)
    with open(path) as handle:
        entry = json.load(handle)
    entry["at"] -= by_seconds
    with open(path, "w") as handle:
        json.dump(entry, handle)


def test_cached_get_json_serves_within_ttl_without_refetching(tmp_path):
    with patch("lib._get_json", return_value={"v": 1}) as mock_get:
        first = cached_get_json("https://x/api", str(tmp_path), ttl=3600)
        second = cached_get_json("https://x/api", str(tmp_path), ttl=3600)
    assert first == second == {"v": 1}
    assert mock_get.call_count == 1  # second read served from disk, no network


def test_cached_get_json_refetches_after_ttl_expires(tmp_path):
    with patch("lib._get_json", side_effect=[{"v": 1}, {"v": 2}]) as mock_get:
        assert cached_get_json("https://x/api", str(tmp_path), ttl=3600) == {"v": 1}
        _age_cache_entry(str(tmp_path), "https://x/api", 10000)
        assert cached_get_json("https://x/api", str(tmp_path), ttl=3600) == {"v": 2}
    assert mock_get.call_count == 2


def test_cached_get_json_serves_stale_when_refresh_fails(tmp_path):
    with patch("lib._get_json", return_value={"v": 1}):
        cached_get_json("https://x/api", str(tmp_path), ttl=3600)
    _age_cache_entry(str(tmp_path), "https://x/api", 10000)
    with patch("lib._get_json", side_effect=RuntimeError("rate limited")):
        result = cached_get_json("https://x/api", str(tmp_path), ttl=3600)
    assert result == {"v": 1}  # stale served rather than failing the render


def test_cached_get_json_raises_when_no_cache_and_fetch_fails(tmp_path):
    with patch("lib._get_json", side_effect=RuntimeError("down")):
        with pytest.raises(RuntimeError):
            cached_get_json("https://x/api", str(tmp_path), ttl=3600)


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


# ── nginx ─────────────────────────────────────────────────────────────────────

def test_acme_cert_paths_match_acme_verify_and_issue_naming():
    assert acme_cert_paths("vmserver", "vm.example.com") == (
        "/opt/acme/cert/vmserver_vm.example.com_fullchain.cer",
        "/opt/acme/cert/vmserver_vm.example.com_key.key",
    )


def _vh(**kw):
    base = {"names": ["a.example.com"], "upstream": "127.0.0.1:9000"}
    base.update(kw)
    return base


def _norm(vhosts, instance="app", sockets=None):
    return normalize_nginx_vhosts({"manage": True, "vhosts": vhosts}, instance, sockets)


def test_nginx_vhosts_derive_acme_tls_paths_and_defaults():
    [v] = _norm({"web": _vh(names=["logs.example.com", "logs-alt.example.com"],
                            acme_account="example_com")}, "vlogs")
    assert v["key"] == "web"
    assert v["name"] == "vlogs_web"
    assert v["domain"] == "logs.example.com logs-alt.example.com"
    assert v["tls"] is True
    assert v["acme_account"] == "example_com"
    assert v["ssl_cert"] == "/opt/acme/cert/vlogs_web_logs.example.com_fullchain.cer"
    assert v["ssl_key"] == "/opt/acme/cert/vlogs_web_logs.example.com_key.key"
    assert v["upstream"] == "127.0.0.1:9000" and v["template"] is None
    assert v["access_log"] == "/var/log/nginx/vlogs_web.access.log"
    assert v["error_log"] == "/var/log/nginx/vlogs_web.error.log"
    assert v["auth_basic"] == [] and v["htpasswd_file"] is None


def test_nginx_vhost_name_override_keeps_old_cert_name():
    [v] = _norm({"x": _vh(name="vmserver", acme_account="a", names=["vm.example.com"])})
    assert v["ssl_cert"] == "/opt/acme/cert/vmserver_vm.example.com_fullchain.cer"


def test_nginx_vhosts_keep_operator_tls_plain_and_order():
    result = _norm({
        "acme": _vh(acme_account="example_com"),
        "static": _vh(ssl_cert="/cert.pem", ssl_key="/key.pem"),
        "plain": _vh(),
    })
    assert [v["key"] for v in result] == ["acme", "static", "plain"]
    assert [v["tls"] for v in result] == [True, True, False]
    assert result[1]["ssl_cert"] == "/cert.pem"
    assert result[2]["ssl_cert"] is None and result[2]["acme_account"] is None


def test_nginx_vhost_auth_basic_sets_htpasswd_file():
    [v] = _norm({"web": _vh(name="svc", auth_basic=[{"username": "admin", "password": "x"}])})
    assert v["htpasswd_file"] == "/etc/nginx/htpasswd/svc"


def test_nginx_vhosts_reject_ambiguous_and_partial_tls():
    with pytest.raises(ValueError, match="both acme_account and ssl_cert/ssl_key"):
        _norm({"w": _vh(acme_account="a", ssl_cert="/c", ssl_key="/k")})
    with pytest.raises(ValueError, match="must set both ssl_cert and ssl_key"):
        _norm({"w": _vh(ssl_cert="/c")})
    with pytest.raises(ValueError, match="must set both ssl_cert and ssl_key"):
        _norm({"w": _vh(ssl_key="/k")})


def test_nginx_vhosts_reject_bad_names():
    with pytest.raises(ValueError, match="`names` must be a non-empty list"):
        _norm({"w": {"upstream": "x:1"}})
    with pytest.raises(ValueError, match="`names` must be a non-empty list"):
        _norm({"w": _vh(names=[])})


def test_nginx_vhosts_upstream_xor_template_and_vars_need_template():
    with pytest.raises(ValueError, match="exactly one of"):
        _norm({"w": {"names": ["a.example.com"]}})
    with pytest.raises(ValueError, match="exactly one of"):
        _norm({"w": _vh(template="salt://x.conf")})
    with pytest.raises(ValueError, match="`vars` is only used with a custom"):
        _norm({"w": _vh(vars={"a": 1})})


def test_nginx_vhosts_reject_bad_key_name_unknown_key_and_empty():
    with pytest.raises(ValueError, match="invalid key"):
        _norm({"bad key": _vh()})
    with pytest.raises(ValueError, match="invalid `name`"):
        _norm({"w": _vh(name="a/b")})
    with pytest.raises(ValueError, match="unknown key"):
        _norm({"w": _vh(bogus=1)})
    with pytest.raises(ValueError, match="vhosts is empty"):
        normalize_nginx_vhosts({"manage": True}, "app")


def test_nginx_template_context_has_reserved_names_and_vars_on_top():
    [v] = _norm({"w": _vh(name="svc", upstream=None, template="salt://t.conf",
                          acme_account="a", vars={"port": 1})}, "app")
    ctx = nginx_template_context(v, {"w": "/run/php/x.sock"})
    assert ctx == {
        "vhost_name": "svc", "domain": "a.example.com", "names": ["a.example.com"],
        "ssl_cert": "/opt/acme/cert/svc_a.example.com_fullchain.cer",
        "ssl_key": "/opt/acme/cert/svc_a.example.com_key.key",
        "access_log": "/var/log/nginx/svc.access.log",
        "error_log": "/var/log/nginx/svc.error.log",
        "htpasswd_file": "", "php_fpm_sockets": {"w": "/run/php/x.sock"}, "port": 1,
    }


def test_nginx_template_context_empty_strings_without_tls_and_reserved_clash():
    [v] = _norm({"w": _vh(upstream=None, template="salt://t.conf")})
    ctx = nginx_template_context(v)
    assert ctx["ssl_cert"] == "" and ctx["ssl_key"] == "" and ctx["php_fpm_sockets"] == {}
    [bad] = _norm({"w": _vh(upstream=None, template="salt://t.conf", vars={"domain": "x"})})
    with pytest.raises(ValueError, match="collide with reserved"):
        nginx_template_context(bad)


# ── php-fpm ───────────────────────────────────────────────────────────────────

def _pools(pools, instance="inst"):
    return normalize_php_pools(pools, instance, "web", "webgrp")


def test_php_pools_defaults_resolved():
    [p] = _pools({"back": {"version": "8.3"}})
    assert p == {
        "key": "back", "name": "inst_back", "version": "8.3", "user": "web", "group": "webgrp",
        "listen": "/run/php/php8.3-fpm-inst_back.sock",
        "listen_owner": "www-data", "listen_group": "www-data", "listen_mode": "0660",
        "error_log": None, "reload": True, "config": "",
        "path": "/etc/php/8.3/fpm/pool.d/inst_back.conf",
    }


def test_php_pools_empty_and_order_and_overrides():
    assert _pools(None) == [] and _pools({}) == []
    result = _pools({"b": {"version": "8.1", "name": "x", "user": "u", "reload": False,
                           "listen": "/run/{pool_name}-{version}.sock"},
                     "a": {"version": "8.10"}})
    assert [p["key"] for p in result] == ["b", "a"]
    assert result[0]["listen"] == "/run/x-8.1.sock"
    assert result[0]["user"] == "u" and result[0]["reload"] is False
    assert result[1]["path"] == "/etc/php/8.10/fpm/pool.d/inst_a.conf"


def test_php_pools_validation():
    with pytest.raises(ValueError, match="quote it"):
        _pools({"a": {"version": 8.3}})
    with pytest.raises(ValueError, match="quote it"):
        _pools({"a": {}})
    with pytest.raises(ValueError, match="must look like"):
        _pools({"a": {"version": "8"}})
    with pytest.raises(ValueError, match="invalid key"):
        _pools({"a b": {"version": "8.3"}})
    with pytest.raises(ValueError, match="unknown key"):
        _pools({"a": {"version": "8.3", "bogus": 1}})
    with pytest.raises(ValueError, match="invalid `name`"):
        _pools({"a": {"version": "8.3", "name": "a b"}})
    with pytest.raises(ValueError, match="listen_mode"):
        _pools({"a": {"version": "8.3", "listen_mode": 660}})


def test_render_php_pool_with_and_without_error_log():
    [p] = _pools({"a": {"version": "8.3", "error_log": "/l/e.log",
                        "config": "pm = dynamic\npm.max_children = 20\n"}})
    assert render_php_pool(p) == (
        "[inst_a]\nuser = web\ngroup = webgrp\n\n"
        "listen = /run/php/php8.3-fpm-inst_a.sock\nlisten.owner = www-data\n"
        "listen.group = www-data\nlisten.mode = 0660\n\n"
        "php_admin_value[error_log] = /l/e.log\nphp_admin_flag[log_errors] = on\n\n"
        "pm = dynamic\npm.max_children = 20\n")
    [q] = _pools({"a": {"version": "8.3", "config": "pm = static"}})
    out = render_php_pool(q)
    assert "error_log" not in out and out.endswith("listen.mode = 0660\n\npm = static\n")


def test_php_reload_command():
    assert php_reload_command("8.3") == "php-fpm8.3 -t && systemctl reload php8.3-fpm"


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


# ── runtimes: layout, nvm, pyenv, tools, env_sh ───────────────────────────────

NVM_BASE = {"rev": "v0.40.1", "repo": "https://github.com/nvm-sh/nvm.git"}
PYENV_BASE = {"rev": "v2.4.0", "repo": "https://github.com/pyenv/pyenv.git", "build_pkgs": ["libssl-dev"]}


def test_runtime_layout_non_root_and_root():
    u = runtime_layout("helium", "/home/helium", "crm")
    assert u == {"nvm_dir": "/home/helium/.nvm", "pyenv_root": "/home/helium/.pyenv",
                 "tools_dir": "/home/helium/.local/bin", "env_sh": "/home/helium/.appsvc/crm.sh",
                 "profile": "/home/helium/.bashrc"}
    r = runtime_layout("root", "/root", "crm")
    assert r == {"nvm_dir": "/usr/local/nvm", "pyenv_root": "/usr/local/pyenv",
                 "tools_dir": "/usr/local/bin", "env_sh": "/etc/profile.d/appsvc-crm.sh",
                 "profile": None}


def test_runtime_paths_explicit_wins_and_profile_false():
    p = runtime_paths("helium", "/home/helium", "crm", {"dir": "{home}/node"},
                      {"root": "/opt/py"}, {"path": "/srv/e.sh", "profile": "{home}/.profile"},
                      scope={"home": "/home/helium"})
    assert (p["nvm_dir"], p["pyenv_root"], p["env_sh"], p["profile"]) == \
        ("/home/helium/node", "/opt/py", "/srv/e.sh", "/home/helium/.profile")
    assert runtime_paths("helium", "/home/helium", "crm", env_sh={"profile": False})["profile"] is None


def test_runtime_paths_errors_name_instance():
    with pytest.raises(ValueError, match="instance crm.*unknown key"):
        runtime_paths("root", "/root", "crm", env_sh={"bogus": 1})
    with pytest.raises(ValueError, match="instance crm.*profile"):
        runtime_paths("root", "/root", "crm", env_sh={"profile": 5})


def test_runtime_placeholders_resolve_in_phase2_root_and_non_root():
    for user, nvm_dir, env_sh in (({"name": "helium"}, "/home/helium/.nvm", "/home/helium/.appsvc/crm.sh"),
                                  ({}, "/usr/local/nvm", "/etc/profile.d/appsvc-crm.sh")):
        p = runtime_paths(user.get("name", "root"), user_home(user), "crm")
        scope = {"nvm_dir": p["nvm_dir"], "pyenv_root": p["pyenv_root"],
                 "tools_dir": p["tools_dir"], "env_sh": p["env_sh"]}
        out = expand({"c": ". {env_sh} && composer install", "py": "{pyenv_root}/versions/x"}, scope)
        assert out["c"] == ". {} && composer install".format(env_sh)
        assert out["py"] == p["pyenv_root"] + "/versions/x"
        assert p["nvm_dir"] == nvm_dir


def test_nvm_plan_inert_without_versions():
    layout = runtime_layout("root", "/root", "crm")
    assert nvm_plan(None, layout, "root") is None
    assert nvm_plan(dict(NVM_BASE), layout, "root") is None
    assert nvm_plan(dict(NVM_BASE, versions=[]), layout, "root") is None


def test_nvm_plan_commands_non_root():
    layout = runtime_layout("helium", "/home/helium", "crm")
    plan = nvm_plan(dict(NVM_BASE, versions=["20", "18"]), layout, "helium")
    assert plan["dir"] == "/home/helium/.nvm" and plan["user"] == "helium"
    assert plan["default"] == "20" and plan["env"] == {"NVM_DIR": "/home/helium/.nvm"}
    assert plan["installs"][0] == {
        "version": "20", "suffix": "20",
        "name": '. "/home/helium/.nvm/nvm.sh" && nvm install 20',
        "unless": '. "/home/helium/.nvm/nvm.sh" && [ "$(nvm version 20)" != "N/A" ]'}
    assert plan["default_cmd"] == {
        "name": '. "/home/helium/.nvm/nvm.sh" && nvm alias default 20',
        "unless": '[ "$(cat /home/helium/.nvm/alias/default 2>/dev/null)" = "20" ]'}
    assert nvm_plan(dict(NVM_BASE, versions=["20"]), runtime_layout("root", "/root", "c"), "root")["user"] is None
    assert plan["build_pkgs"] == []
    assert nvm_plan(dict(NVM_BASE, versions=["20"], build_pkgs=["git", "curl"]), layout, "helium")["build_pkgs"] == ["git", "curl"]


def test_nvm_plan_validation():
    layout = runtime_layout("root", "/root", "crm")
    for bad in ([20], [3.1], "20", [""], ["a b"], ["$(x)"], ["20", "20"]):
        with pytest.raises(ValueError, match="nvm"):
            nvm_plan(dict(NVM_BASE, versions=bad), layout, "root")
    with pytest.raises(ValueError, match="quote it"):
        nvm_plan(dict(NVM_BASE, versions=[20]), layout, "root")
    with pytest.raises(ValueError, match="unknown key"):
        nvm_plan(dict(NVM_BASE, versions=["20"], bogus=1), layout, "root")
    with pytest.raises(ValueError, match="absolute path"):
        nvm_plan(dict(NVM_BASE, versions=["20"], dir='/a"b'), layout, "root")
    with pytest.raises(ValueError, match="nvm:build_pkgs"):
        nvm_plan(dict(NVM_BASE, versions=["20"], build_pkgs="git"), layout, "root")


def test_pyenv_plan_commands_and_validation():
    layout = runtime_layout("helium", "/home/helium", "crm")
    plan = pyenv_plan(dict(PYENV_BASE, versions=["3.8.13", "3.10"]), layout, "helium")
    assert plan["installs"][0] == {
        "version": "3.8.13", "suffix": "3_8_13",
        "name": "PYENV_ROOT=/home/helium/.pyenv /home/helium/.pyenv/bin/pyenv install -s 3.8.13",
        "unless": "test -x /home/helium/.pyenv/versions/3.8.13/bin/python"}
    assert plan["default_cmd"]["name"] == "PYENV_ROOT=/home/helium/.pyenv /home/helium/.pyenv/bin/pyenv global 3.8.13"
    assert plan["default_cmd"]["unless"] == '[ "$(cat /home/helium/.pyenv/version 2>/dev/null)" = "3.8.13" ]'
    assert plan["build_pkgs"] == ["libssl-dev"]
    assert pyenv_plan(dict(PYENV_BASE), layout, "helium") is None
    with pytest.raises(ValueError, match="quote it"):
        pyenv_plan(dict(PYENV_BASE, versions=[3.10]), layout, "helium")
    with pytest.raises(ValueError, match="build_pkgs"):
        pyenv_plan(dict(PYENV_BASE, versions=["3.8"], build_pkgs="gcc"), layout, "helium")
    assert pyenv_plan(dict(PYENV_BASE, versions=["3.8"], root="/opt/py"), layout, "root")["root"] == "/opt/py"


def test_runtime_state_suffix():
    assert runtime_state_suffix("3.8.13") == "3_8_13"
    assert runtime_state_suffix("lts/iron") == "lts_iron"


def test_normalize_tools_defaults_and_validation():
    layout = runtime_layout("helium", "/home/helium", "crm")
    out = normalize_tools({"composer": {"source": "https://x/c.phar", "source_hash": "https://x/c.sha256"},
                           "b": {"source": "https://x/b", "mode": "700", "target": "/opt/b"}},
                          layout, "helium", "helium")
    assert out[0] == ("composer", {"name": "/home/helium/.local/bin/composer", "source": "https://x/c.phar",
                                   "source_hash": "https://x/c.sha256", "user": "helium", "group": "helium",
                                   "mode": "755", "makedirs": True})
    assert out[1][1]["name"] == "/opt/b" and out[1][1]["skip_verify"] is True and "source_hash" not in out[1][1]
    assert normalize_tools(None, layout, "u", "g") == []
    for bad in ({"a/b": {"source": "x"}}, {"..": {"source": "x"}}, {"a": {}}, {"a": {"source": "x", "z": 1}},
                {"a": {"source": "x", "target": "rel"}}, {"a": {"source": "x", "mode": 755}}, {"a": "x"}):
        with pytest.raises(ValueError):
            normalize_tools(bad, layout, "u", "g")


def test_render_env_sh_sections_and_dedup():
    body = render_env_sh({"name": "crm", "nvm_dir": "/n", "pyenv_root": "/p",
                          "tool_dirs": ["/a", "/b", "/a"]})
    assert body == (
        "# Managed by salt (appsvc instance crm) - do not edit.\n"
        'export NVM_DIR="/n"\n'
        '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"\n'
        'export PYENV_ROOT="/p"\n'
        'export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"\n'
        'export PATH="/a:/b:$PATH"\n')
    only_tools = render_env_sh({"name": "c", "tool_dirs": ["/t"]})
    assert "NVM_DIR" not in only_tools and "PYENV_ROOT" not in only_tools and "/t:$PATH" in only_tools


def _settings(**kw):
    s = {"name": "crm", "nvm": dict(NVM_BASE), "pyenv": dict(PYENV_BASE),
         "user": {"name": "helium", "group": "helium"}}
    s.update(kw)
    return s


def test_runtime_plans_inert_by_default():
    plans = runtime_plans(_settings())
    assert plans["nvm"] is None and plans["pyenv"] is None
    assert plans["tools"] == [] and plans["env_sh"] is None


def test_runtime_plans_env_sh_non_root_and_root():
    s = _settings(nvm=dict(NVM_BASE, versions=["20"]),
                  tools={"composer": {"source": "https://x/c.phar"}})
    e = runtime_plans(s)["env_sh"]
    assert (e["path"], e["owner"], e["group"], e["profile"]) == \
        ("/home/helium/.appsvc/crm.sh", "helium", "helium", "/home/helium/.bashrc")
    assert e["profile_line"] == '[ -f "/home/helium/.appsvc/crm.sh" ] && . "/home/helium/.appsvc/crm.sh"  # appsvc crm'
    assert 'export PATH="/home/helium/.local/bin:$PATH"' in e["body"]
    s["user"] = {"name": "root"}
    e = runtime_plans(s)["env_sh"]
    assert (e["path"], e["owner"], e["profile"]) == ("/etc/profile.d/appsvc-crm.sh", "root", None)
    s["shell_env"] = {"profile": False}
    s["user"] = {"name": "helium", "group": "helium"}
    assert runtime_plans(s)["env_sh"]["profile"] is None


def test_runtime_plans_errors_name_instance():
    with pytest.raises(ValueError, match="instance crm: nvm"):
        runtime_plans(_settings(nvm=dict(NVM_BASE, versions=[20])))


def test_env_sh_placeholder_not_shadowed_by_shell_env_settings():
    # The override key is `shell_env`, so an instance that sets it still gets the
    # resolved path for "{env_sh}" (a same-named settings key would be folded into
    # expand's scope and render the dict's repr).
    settings = {"shell_env": {"profile": False}, "cmd": ". {env_sh} && composer install"}
    out = expand(settings, {"env_sh": "/home/helium/.appsvc/crm.sh"})
    assert out["cmd"] == ". /home/helium/.appsvc/crm.sh && composer install"



# --- logrotate ----------------------------------------------------------------

def _pool(key, version, error_log):
    return {"key": key, "version": version, "error_log": error_log}


def _vhost(key, access_log, error_log):
    return {"key": key, "access_log": access_log, "error_log": error_log}


def test_logrotate_groups_nginx_and_php_per_version():
    plan = logrotate_plan(
        {}, [_pool("a", "8.3", "/srv/log/php/a.log"), _pool("b", "8.1", "/srv/log/php/b.log"),
             _pool("c", "8.3", "/srv/log/php/c.log")],
        [_vhost("w", "/srv/log/nginx/w.access.log", "/srv/log/nginx/w.error.log")],
        "helium", "helium")
    assert [s["paths"] for s in plan["stanzas"]] == [
        ["/srv/log/nginx/w.access.log", "/srv/log/nginx/w.error.log"],
        ["/srv/log/php/a.log", "/srv/log/php/c.log"],
        ["/srv/log/php/b.log"]]
    assert plan["stanzas"][0]["postrotate"] == "/usr/sbin/nginx -s reopen"
    assert plan["stanzas"][1]["postrotate"] == php_reopen_command("8.3")
    body = render_logrotate(plan, "crm")
    assert "/srv/log/nginx/w.access.log\n/srv/log/nginx/w.error.log {" in body
    assert "    create 640 helium helium" in body and "    rotate 31" in body
    assert body.count("postrotate") == 3


def test_logrotate_skips_distro_nginx_logs_and_pools_without_error_log():
    plan = logrotate_plan({}, [_pool("a", "8.3", None)],
                          [_vhost("w", "/var/log/nginx/w.access.log", "/var/log/nginx/w.error.log")],
                          "root", "root")
    assert plan["stanzas"] == []


def test_logrotate_duplicate_path_raises():
    with pytest.raises(ValueError, match="declared by both"):
        logrotate_plan({}, [_pool("a", "8.3", "/srv/x.log")], [_vhost("w", "/srv/x.log", "/srv/y.log")],
                       "u", "u")


@pytest.mark.parametrize("conf", [{"rotate": "31"}, {"frequency": "often"}, {"mode": 640},
                                  {"skip": "/var/log/*"}, {"bogus": 1}])
def test_logrotate_rejects_bad_options(conf):
    with pytest.raises(ValueError):
        logrotate_plan(conf, [], [], "u", "u")


def test_logrotate_relative_path_raises():
    with pytest.raises(ValueError, match="absolute"):
        logrotate_plan({}, [_pool("a", "8.3", "log/a.log")], [], "u", "u")
