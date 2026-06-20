import json
import os
import sys
from collections import OrderedDict
from unittest.mock import MagicMock, patch

import pytest
import yaml

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from lib import (
    deep_format, expand,
    merge,
    normalize_osarch, archive_path, tar_extract_command,
    repo_from_source, repo_url, latest_from_release, resolve_latest,
    GITHUB_RELEASES_URL, GRAFANA_VERSIONS_URL, GRAFANA_PACKAGES_URL,
    cached_get_json, _cache_path,
    select_commands,
    render_config, render_unit, merge_args, join_args,
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
        "name": "victorialogs",
    }
    result = expand(mapping, scope={"type": "logs"})
    assert result["install_dir"] == "/opt/services/victorialogs"
    assert result["args"] == "--config=/opt/services/victorialogs/config.yml"
    assert result["exec"] == "/opt/services/victorialogs/victorialogs --config=/opt/services/victorialogs/config.yml"


def test_expand_does_not_mutate_input():
    mapping = {"install_dir": "/opt/{name}", "name": "vl"}
    expand(mapping)
    assert mapping == {"install_dir": "/opt/{name}", "name": "vl"}


def test_expand_resolves_data_dirs_list_through_install_dir():
    # fetch_archive's svc.data_dirs lean on expand resolving a list of strings
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


# ── fetch ─────────────────────────────────────────────────────────────────────

def test_normalize_osarch_maps_known_aliases_and_passes_through_others():
    assert normalize_osarch("x86_64") == "amd64"
    assert normalize_osarch("aarch64") == "arm64"
    assert normalize_osarch("amd64") == "amd64"


def test_archive_path_joins_cache_dir_kind_and_url_basename():
    source = "https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v1.101.0/victoria-metrics-linux-amd64-v1.101.0.tar.gz"
    assert archive_path("/var/cache/salt/binsvc/", "victoriametrics", source) == (
        "/var/cache/salt/binsvc/victoriametrics/victoria-metrics-linux-amd64-v1.101.0.tar.gz"
    )


def test_tar_extract_command_includes_optional_args_and_unpack():
    assert tar_extract_command("/cache/a.tar.gz", "/opt/app") == (
        "tar --no-same-owner --directory /opt/app --extract --file /cache/a.tar.gz"
    )
    assert tar_extract_command("/cache/a.tar.gz", "/opt/app", args="--strip-components=1", unpack="binary") == (
        "tar --strip-components=1 --no-same-owner --directory /opt/app --extract --file /cache/a.tar.gz binary"
    )


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


# ── systemd ───────────────────────────────────────────────────────────────────

def test_render_unit_produces_ini_with_repeated_keys_for_lists():
    sections = OrderedDict([
        ("Unit", OrderedDict([("Description", "victorialogs vl_main"), ("After", ["network.target", "disk.target"])])),
        ("Service", OrderedDict([("Type", "simple"), ("ExecStart", "/opt/app/bin -arg=1")])),
        ("Install", OrderedDict([("WantedBy", "multi-user.target")])),
    ])
    assert render_unit(sections) == (
        "[Unit]\n"
        "Description=victorialogs vl_main\n"
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


def test_join_args_allows_prefixed_flags_for_double_dash_cli():
    assert join_args([{"-web.listen-address": "127.0.0.1:9100"}]) == "--web.listen-address=127.0.0.1:9100"


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


def test_merge_args_returns_empty_list_for_no_layers():
    assert merge_args() == []
    assert merge_args(None, None) == []
