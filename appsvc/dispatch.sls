#!pyobjects
# vim: set ft=python:

# Building-block dispatch for one instance: which blocks run, in which order,
# and how their requisites connect. Kept out of init.sls so tests/test_dispatch.py
# can run it against fake state factories and check that every requisite
# points at a state that exists - for every `appsvc:filter block:` selection.

from salt://appsvc/lib/core.py import BLOCKS
from salt://appsvc/lib/web.py import php_fpm_sockets

from salt://appsvc/blocks/install_dir.sls import install_dir
from salt://appsvc/blocks/fetch.sls import fetch_source
from salt://appsvc/blocks/venv.sls import python_venv
from salt://appsvc/blocks/user_ssh.sls import user_and_ssh
from salt://appsvc/blocks/dirs.sls import dirs
from salt://appsvc/blocks/pyenv.sls import pyenv
from salt://appsvc/blocks/nvm.sls import nvm
from salt://appsvc/blocks/tools.sls import tools
from salt://appsvc/blocks/env_sh.sls import env_sh
from salt://appsvc/blocks/sources.sls import sources
from salt://appsvc/blocks/config_file.sls import config_files
from salt://appsvc/blocks/php_fpm.sls import php_fpm
from salt://appsvc/blocks/commands.sls import run_commands
from salt://appsvc/blocks/systemd_unit.sls import systemd_unit
from salt://appsvc/blocks/cron.sls import cron
from salt://appsvc/blocks/nginx_vhost.sls import nginx_vhost
from salt://appsvc/blocks/logrotate.sls import logrotate


def dispatch(prefix, settings, blocks=None):
    """Run the building blocks an instance's merged settings call for, in a
    fixed order: user/ssh, install_dir (ahead of config - a config entry with
    makedirs would otherwise create the install dir root-owned before the
    service user's ownership is applied), dirs (before sources, so a
    checkout's parent exists; a dir inside a source target fails loud), the
    runtimes (pyenv, nvm, tools, env_sh), sources (before config, so a config
    entry can write into a checkout, e.g. a .env.local - and such an entry
    `require`s its source, so a failed clone never leaves a makedirs-created
    target behind), config, the svc fetch, venv (after fetch -
    venv.requirements_files may point at a requirements.txt that arrives inside
    the fetched archive), php_fpm pools, pre-systemd commands, systemd units,
    post-systemd commands, cron, then nginx (which gets the php_fpm
    {pool_key: socket} map), then logrotate (composed from the pool and vhost
    logs). Source/fetch/config/venv/runtime changes are wired via the `changed`
    requisite-list contract so systemd restarts whenever the code, binary,
    config, or requirement set actually changed. Commands with `onchanges` get
    the per-key source refs via `refs`.

    `blocks` (a set of BLOCKS names, from `appsvc:filter block:`; None = all)
    limits which blocks emit states. A skipped block contributes no
    requisites: `changed` only holds what this run applies, the php_fpm socket
    map is computed from pillar instead, a config entry inside a skipped
    source drops its `require` (the checkout is assumed to exist), and a
    command whose `onchanges` only watches skipped blocks is not emitted."""

    def on(block):
        return blocks is None or block in blocks

    skipped = set(BLOCKS) - set(blocks) if blocks is not None else set()

    if on("user"):
        user_and_ssh(prefix, settings)
    if on("install_dir"):
        install_dir(prefix, settings)
    if on("dirs"):
        dirs(prefix, settings)

    changed = []
    if on("pyenv"):
        changed += list(pyenv(prefix, settings) or [])
    if on("nvm"):
        changed += list(nvm(prefix, settings) or [])
    if on("tools"):
        changed += list(tools(prefix, settings) or [])
    if on("shell_env"):
        env_sh(prefix, settings)

    source_refs = sources(prefix, settings) if on("sources") else {}
    changed += list(source_refs.values())
    if on("config"):
        changed += list(config_files(prefix, settings, source_refs) or [])

    if settings.get("svc") and on("svc"):
        changed = list(fetch_source(prefix, settings) or []) + changed
    if on("venv"):
        changed = list(python_venv(prefix, settings) or []) + changed

    if on("php_fpm"):
        php_sockets = php_fpm(prefix, settings)
    else:
        php_sockets = php_fpm_sockets(settings, prefix[-1])

    refs = {"sources": source_refs}
    running = None
    if on("commands"):
        run_commands(prefix, settings, phase="pre", require=changed, refs=refs, skipped=skipped)
    if on("systemd"):
        running = systemd_unit(prefix, settings, watch=changed)
    if on("commands"):
        run_commands(prefix, settings, phase="post", require=running, refs=refs, skipped=skipped)

    if on("cron"):
        cron(prefix, settings)
    if on("nginx"):
        nginx_vhost(prefix, settings, php_sockets)
    if on("logrotate"):
        logrotate(prefix, settings)
