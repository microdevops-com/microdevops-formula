#!pyobjects
# vim: set ft=python:

from salt://binsvc/lib.py import venv_requirement_paths, venv_build_command, venv_guard_command, VENV_STAMP_NAME

# Generic mechanism for running a Python daemon under binsvc: create/maintain a
# venv matching a declared requirement set. Driven by the top-level `venv:`
# key (not svc.venv) - a PyPI-distributed daemon (venv.requirements: [...], no
# svc block at all) is a valid instance. See PATCH.md phase 2 and
# docs/extending-with-app-blocks.md litmus test #2 (generic gap -> generic
# block, not app-specific code).
#
# Runs after fetch in dispatch (init.sls): venv.requirements_files may point at
# a requirements.txt that arrives inside the fetched archive, whose content
# render time can't know.


def python_venv(prefix, settings):
    """Ensure the venv exists and matches the declared requirement set.
    No-op unless venv.manage. Returns [Cmd(sid + "_venv")] - the restart
    trigger dispatch folds into the changed/watch contract."""

    venv = settings.get("venv") or {}
    if not venv.get("manage", False):
        return []

    install_dir = settings["install_dir"]
    sid = "_".join(prefix)

    paths = venv_requirement_paths(venv, install_dir)

    # The venv stays root-owned (Cmd.run defaults to root, same as fetch's
    # archive extraction) - the service user gets read+execute only, not write.
    # Consistent with fetch's "a compromised service can't rewrite its own
    # binary" rule; writable state still goes through svc.data_dirs.
    require = []
    if venv.get("pkgs"):
        # Guarded: an operator whose base state already installs python3-venv
        # can set pkgs: [], and Salt's pkg.installed rejects an empty pkgs list.
        Pkg.installed(sid + "_pkgs", pkgs=venv["pkgs"])
        require.append(Pkg(sid + "_pkgs"))

    if venv.get("requirements"):
        # Outside {venv_dir} on purpose: a recreate_on_change --clear rebuild
        # must not eat the requirements file mid-run. paths[0] is this file -
        # venv_requirement_paths always puts the inline path first when present.
        File.managed(sid + "_requirements",
                     name=paths[0],
                     contents="\n".join(venv["requirements"]),
                     user="root", group="root", mode="644",
                     makedirs=True)
        require.append(File(sid + "_requirements"))

    # Inside {venv_dir} on purpose: a --clear recreate wipes it along with the
    # rest of the venv, so a stale stamp can never survive a rebuild.
    stamp_path = venv["dir"].rstrip("/") + "/" + VENV_STAMP_NAME

    Cmd.run(sid + "_venv",
            name=venv_build_command(venv, paths, stamp_path),
            unless=venv_guard_command(venv, paths, stamp_path),
            shell="/bin/bash",
            require=require)

    return [Cmd(sid + "_venv")]
