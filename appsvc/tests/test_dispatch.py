import fnmatch
import os

import pytest
import yaml

import fake_pyobjects
from appsvc_lib.core import BLOCKS, deep_format, lift_dir_specs, merge, split_dir_perms
from appsvc_sls.dispatch import dispatch

ROOT = os.path.join(os.path.dirname(__file__), "..")


def _yaml(path):
    with open(os.path.join(ROOT, path)) as f:
        return yaml.safe_load(f) or {}


SCOPE = {"type": "t", "user_name": "helium", "user_group": "helium", "home": "/home/helium",
         "nvm_dir": "/home/helium/.nvm", "pyenv_root": "/home/helium/.pyenv",
         "tools_dir": "/home/helium/.local/bin", "env_sh": "/home/helium/.appsvc/app.sh",
         "exec": "/opt/vm/vmagent", "args": "-a=1", "svc_target": "/opt/vm/x.tar.gz",
         "tag": "v1.0.0", "version": "1.0.0", "osarch": "amd64", "venv_dir": "/opt/vm/venv"}

# Every block with something to emit, and every cross-block link: config inside
# a source (require), commands onchanges on a source, pre/post commands, nvm +
# tools + env_sh, php pool -> nginx template sockets, systemd units watching
# `changed`, cron, logrotate composed from pool and vhost logs.
APP = {
    "install_dir": {"name": "/var/www/helium/crm", "group": "www-data", "mode": "750"},
    "user": {"manage": True, "name": "helium", "group": "helium", "shell": "/bin/bash",
             "home": {"name": "/var/www/helium", "group": "www-data", "mode": "750"}},
    "dirs": {"php_log": "/var/www/helium/crm/log/php", "nginx_log": "/var/www/helium/crm/log/nginx"},
    "nvm": {"versions": ["22"]},
    "tools": {"composer": {"source": "https://getcomposer.org/download/2.8.6/composer.phar"}},
    "sources": {
        "back": {"git": "git@gitlab.example.com:g/back.git", "target": "/var/www/helium/crm/back"},
        "front": {"git": "git@gitlab.example.com:g/front.git", "target": "/var/www/helium/crm/front",
                  "once": True},
    },
    "config": {"env_local": {"name": "/var/www/helium/crm/back/.env.local", "contents": "A=1\n"}},
    "php_fpm": {"pools": {"back": {"version": "8.3",
                                   "log": {"error": "/var/www/helium/crm/log/php/back.error.log",
                                           "slow": "/var/www/helium/crm/log/php/back.slow.log"}}}},
    "commands": {
        "composer_install": {"cmd": "composer install", "phase": "pre", "onchanges": ["sources:back"]},
        "warmup": {"cmd": "bin/console cache:warmup"},
    },
    "systemd": {"units": {"consumer": {"Service": {"ExecStart": "/usr/bin/php bin/console messenger:consume"}}}},
    "cron": {"sessions": {"schedule": "0 * * * *", "cmd": "find /tmp -mtime +10 -delete"}},
    "nginx": {"manage": True, "vhosts": {"back": {
        "names": ["app.example.com"], "acme_account": "example_com",
        "template": "salt://x/back.conf",
        "log": {"access": "/var/www/helium/crm/log/nginx/back.access.log",
                "error": "/var/www/helium/crm/log/nginx/back.error.log"}}}},
}

# A binary service from a bundled preset: svc fetch -> systemd watch.
VM = {"preset": "vmagent", "install_dir": "/opt/vm", "user": {"manage": True, "name": "vm", "group": "vm"}}


def _settings(name, instance):
    preset = _yaml("presets/{}.yaml".format(instance["preset"])) if "preset" in instance else {}
    settings = merge(*(lift_dir_specs(layer) for layer in (_yaml("defaults.yaml"), preset, instance)))
    settings["name"] = name  # as init.sls does
    settings = split_dir_perms(settings)
    return deep_format(settings, dict(SCOPE, name=name))


def _emit(blocks):
    fake_pyobjects.reset()
    for name, instance in (("app", APP), ("vm", VM)):
        dispatch(["appsvc", name], _settings(name, instance), blocks)
    return dict(fake_pyobjects.STATES)


# Which block emitted a state, from its ID (appsvc_<instance>_<part>...).
ID_BLOCKS = [
    ("*_user*", "user"), ("*_ssh_*", "user"), ("*_install_dir", "install_dir"),
    ("*_data_dir_*", "svc"), ("*_dir_*", "dirs"),
    ("*_pyenv_*", "pyenv"), ("*_nvm_*", "nvm"), ("*_tool_*", "tools"), ("*_tools_*", "tools"),
    ("*_env_sh*", "shell_env"), ("*_source_*", "sources"), ("*_config_*", "config"),
    ("*_venv*", "venv"), ("*_php_fpm_*", "php_fpm"), ("*_cmd_*", "commands"),
    ("*_systemd_*", "systemd"), ("*_cron_*", "cron"), ("*_nginx*", "nginx"),
    ("*_logrotate*", "logrotate"),
]


def _block_of(state_id):
    for pattern, block in ID_BLOCKS:
        if fnmatch.fnmatchcase(state_id, pattern):
            return block
    return "svc"


def test_full_dispatch_covers_every_block():
    emitted = {_block_of(state_id) for _, state_id in _emit(None)}
    assert emitted == set(BLOCKS) - {"pyenv", "venv"}  # not used by either instance


@pytest.mark.parametrize("blocks", [None] + [{b} for b in BLOCKS] + [
    {"cron", "nginx"}, {"config", "commands"}, {"sources", "commands"}, {"systemd", "commands"},
    {"svc", "systemd"}, set(BLOCKS) - {"sources"}, set(BLOCKS) - {"php_fpm"},
])
def test_filtered_dispatch_has_no_dangling_requisites(blocks):
    states = _emit(blocks)
    assert fake_pyobjects.dangling() == []
    if blocks is not None:
        assert {_block_of(state_id) for _, state_id in states} <= blocks


def test_skipped_sources_drop_onchanges_command_and_config_require():
    states = _emit({"config", "commands"})
    assert ("cmd", "appsvc_app_cmd_composer_install") not in states
    assert ("cmd", "appsvc_app_cmd_warmup") in states
    _, kwargs = states[("file", "appsvc_app_config_env_local")]
    assert "require" not in kwargs
    with_sources = _emit({"sources", "config", "commands"})
    assert with_sources[("cmd", "appsvc_app_cmd_composer_install")][1]["onchanges"] == [
        fake_pyobjects.Ref("git", "appsvc_app_source_back")]
    assert with_sources[("file", "appsvc_app_config_env_local")][1]["require"] == [
        fake_pyobjects.Ref("git", "appsvc_app_source_back")]


def test_nginx_alone_still_gets_php_sockets():
    full = _emit(None)
    alone = _emit({"nginx"})
    key = ("file", "appsvc_app_nginx_back_vhost")
    assert alone[key] == full[key]
    assert alone[key][1]["context"]["php_fpm_sockets"] == {"back": "/run/php/php8.3-fpm-app_back.sock"}


def test_systemd_alone_restarts_only_on_unit_file():
    _, kwargs = _emit({"systemd"})[("cmd", "appsvc_app_systemd_consumer_restart")]
    assert kwargs["onchanges"] == [fake_pyobjects.Ref("file", "appsvc_app_systemd_consumer_unit")]


def test_home_and_install_dir_permissions():
    states = _emit({"user", "install_dir"})
    function, home = states[("file", "appsvc_app_user_home")]
    assert function == "directory"
    assert (home["name"], home["user"], home["group"], home["mode"]) == \
        ("/var/www/helium", "helium", "www-data", "750")
    assert home["require"] == [fake_pyobjects.Ref("user", "appsvc_app_user")]
    _, app = states[("file", "appsvc_app_install_dir")]
    assert (app["group"], app["mode"]) == ("www-data", "750")
    _, vm = states[("file", "appsvc_vm_install_dir")]
    assert (vm["user"], vm["group"]) == ("vm", "vm") and "mode" not in vm
    assert ("file", "appsvc_vm_user_home") not in states
