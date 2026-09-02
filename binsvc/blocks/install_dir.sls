#!pyobjects
# vim: set ft=python:

# Split out of fetch_archive's leading File.directory so the install dir
# exists (and is service-user-owned) even for instances with no `svc` at all -
# a venv-only, PyPI-installed daemon still needs somewhere to live.


def install_dir(prefix, settings):
    """File.directory settings["install_dir"], owned by the service user.
    No-op when install_dir is unset. Returns nothing - creating a directory is
    not a restart trigger."""

    path = settings.get("install_dir")
    if not path:
        return

    owner = settings.get("user", {})
    sid = "_".join(prefix)

    File.directory(sid + "_install_dir",
                   name=path,
                   user=owner.get("name", "root"),
                   group=owner.get("group", "root"),
                   makedirs=True)
