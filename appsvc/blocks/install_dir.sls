#!pyobjects
# vim: set ft=python:

from salt://appsvc/lib/core.py import dir_perms

# Split out of fetch_archive's leading File.directory so the install dir
# exists (and is service-user-owned) even for instances with no `svc` at all -
# a venv-only, PyPI-installed daemon still needs somewhere to live.


def install_dir(prefix, settings):
    """File.directory settings["install_dir"], owned by the service user
    unless install_dir.{user,group} say otherwise; install_dir.mode if set
    (the directory itself, never recursive). No-op when install_dir is unset.
    Returns nothing - creating a directory is not a restart trigger."""

    entry = dir_perms(settings).get("install_dir")
    if not entry:
        return

    sid = "_".join(prefix)
    kwargs = dict(name=entry["name"], user=entry["user"], group=entry["group"], makedirs=True)
    if entry.get("mode"):
        kwargs["mode"] = entry["mode"]
    File.directory(sid + "_install_dir", **kwargs)
