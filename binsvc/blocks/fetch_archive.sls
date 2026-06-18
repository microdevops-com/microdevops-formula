#!pyobjects
# vim: set ft=python:

from salt://binsvc/lib.py import archive_path, tar_extract_command, version_check, deep_format

# Generalizes exporter/macro.jinja's download/tar/move/executable macros and
# victoriametrics/_setup.sls's archive handling into one reusable block.


def fetch_archive(prefix, settings):
    """Download an archive (or bare binary), optionally unpack and/or move it
    into install_dir, and ensure it is executable. Returns the list of
    pyobjects requisite references that should trigger a restart when they
    change - the dispatcher wires these into the systemd block."""

    svc = settings["svc"]
    install_dir = settings["install_dir"]
    owner = settings.get("user", {})
    sid = "_".join(prefix)

    File.directory(sid + "_install_dir",
                   name=install_dir,
                   user=owner.get("name", "root"),
                   group=owner.get("group", "root"),
                   makedirs=True)

    source = svc["source"]
    archive = archive_path(settings.get("cache_dir", "/var/cache/salt/binsvc"), settings["type"], source)
    source_hash = svc.get("source_hash")

    archive_kwargs = dict(name=archive, source=source, makedirs=True)
    if source_hash:
        archive_kwargs["source_hash"] = source_hash
    else:
        archive_kwargs["skip_verify"] = True
    File.managed(sid + "_archive", **archive_kwargs)

    changed = [File(sid + "_archive")]

    # {file} only becomes known once the archive's local cache path is
    # computed above, so tar.unpack/move.{src,dst} get a narrow expansion
    # pass here rather than in init.sls's generic settings expansion.
    file_scope = {"file": archive, "install_dir": install_dir}

    tar = svc.get("tar")
    if tar is not None:
        tar = deep_format(tar, file_scope)
        command = tar_extract_command(
            archive, install_dir, args=tar.get("args", ""), unpack=tar.get("unpack", "")
        )

        extract_kwargs = dict(name=command, shell="/bin/bash", user="root", group="root",
                              require=[File(sid + "_archive")])

        version = svc.get("version")
        binary = svc.get("exec", "").split()[0] if svc.get("exec") else None
        if version and binary:
            extract_kwargs["unless"] = [version_check(binary, version)]

        Cmd.run(sid + "_extract", **extract_kwargs)
        changed = [Cmd(sid + "_extract")]

    move = svc.get("move")
    if move is not None:
        move = deep_format(move, file_scope)
        File.rename(sid + "_move", name=move["dst"], source=move["src"],
                    force=True, makedirs=True, require=changed)
        changed = [File(sid + "_move")]

    if svc.get("exec"):
        File.managed(sid + "_executable",
                     name=svc["exec"].split()[0],
                     user="root", group="root", mode="755",
                     require=changed)

    # Service-owned writable state. Extraction runs as root with --no-same-owner,
    # so anything the archive *ships* lands root-owned; dirs the service must
    # write into (e.g. Grafana's data/db, plugins, logs) must be the service
    # user's. Kept distinct from the root-owned program files on purpose - a
    # compromised service can't rewrite its own binary. recurse fixes ownership
    # of any contents the tarball shipped. Not added to `changed`: an ownership
    # fixup isn't a "new binary" restart trigger. data_dirs are already concrete
    # here (init.sls expands {install_dir}/... before dispatch).
    for index, data_dir in enumerate(svc.get("data_dirs", [])):
        File.directory(sid + "_data_dir_" + str(index),
                       name=data_dir,
                       user=owner.get("name", "root"),
                       group=owner.get("group", "root"),
                       makedirs=True,
                       recurse=["user", "group"],
                       require=changed)

    return changed
