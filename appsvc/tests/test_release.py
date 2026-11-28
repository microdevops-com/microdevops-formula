import json
from unittest.mock import MagicMock, patch

import pytest

from appsvc_lib.release import (
    GITHUB_RELEASES_LIST_URL,
    GRAFANA_PACKAGES_URL,
    GRAFANA_VERSIONS_URL,
    VENV_INLINE_REQUIREMENTS_NAME,
    VENV_STAMP_NAME,
    _cache_path,
    _get_json,
    archive_path,
    cached_get_json,
    fetch_kind,
    fetch_target,
    latest_from_release,
    normalize_osarch,
    repo_from_source,
    repo_url,
    resolve_latest,
    source_basename,
    tar_extract_command,
    venv_build_command,
    venv_digest_command,
    venv_guard_command,
    venv_requirement_paths,
)


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

    with patch("appsvc_lib.release.requests.get", return_value=mock_response) as mock_get:
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
    with patch("appsvc_lib.release.requests.get", return_value=mock_response) as mock_get:
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

    with patch("appsvc_lib.release.requests.get", return_value=resp) as mock_get:
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

    with patch("appsvc_lib.release.requests.get", return_value=resp):
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

    with patch("appsvc_lib.release.requests.get", side_effect=[page1, page2]) as mock_get:
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
    with patch("appsvc_lib.release.requests.get", return_value=resp) as mock_get:
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

    with patch("appsvc_lib.release.requests.get", side_effect=[versions_response, packages_response]) as mock_get:
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

    with patch("appsvc_lib.release.requests.get", return_value=packages_response) as mock_get:
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
    with patch("appsvc_lib.release.requests.get", return_value=resp) as mock_get:
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
    with patch("appsvc_lib.release.requests.get", return_value=resp) as mock_get:
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
    with patch("appsvc_lib.release._get_json", return_value={"v": 1}) as mock_get:
        first = cached_get_json("https://x/api", str(tmp_path), ttl=3600)
        second = cached_get_json("https://x/api", str(tmp_path), ttl=3600)
    assert first == second == {"v": 1}
    assert mock_get.call_count == 1  # second read served from disk, no network


def test_cached_get_json_refetches_after_ttl_expires(tmp_path):
    with patch("appsvc_lib.release._get_json", side_effect=[{"v": 1}, {"v": 2}]) as mock_get:
        assert cached_get_json("https://x/api", str(tmp_path), ttl=3600) == {"v": 1}
        _age_cache_entry(str(tmp_path), "https://x/api", 10000)
        assert cached_get_json("https://x/api", str(tmp_path), ttl=3600) == {"v": 2}
    assert mock_get.call_count == 2


def test_cached_get_json_serves_stale_when_refresh_fails(tmp_path):
    with patch("appsvc_lib.release._get_json", return_value={"v": 1}):
        cached_get_json("https://x/api", str(tmp_path), ttl=3600)
    _age_cache_entry(str(tmp_path), "https://x/api", 10000)
    with patch("appsvc_lib.release._get_json", side_effect=RuntimeError("rate limited")):
        result = cached_get_json("https://x/api", str(tmp_path), ttl=3600)
    assert result == {"v": 1}  # stale served rather than failing the render


def test_cached_get_json_raises_when_no_cache_and_fetch_fails(tmp_path):
    with patch("appsvc_lib.release._get_json", side_effect=RuntimeError("down")):
        with pytest.raises(RuntimeError):
            cached_get_json("https://x/api", str(tmp_path), ttl=3600)
