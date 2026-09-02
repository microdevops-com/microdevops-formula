#!pyobjects
# vim: set ft=python:

from salt://binsvc/lib.py import archive_path, tar_extract_command, deep_format, fetch_kind, fetch_target

# Generalizes exporter/macro.jinja's download/tar/move/executable macros and
# victoriametrics/_setup.sls's archive handling into one reusable block.
# Renamed from fetch_archive.sls: fetch_kind (lib.py) now picks between two
# strategies - "archive" (this file's original behavior, unchanged below) and
# "file" (a bare script/binary compared as-is via File.managed, no cache hop) -
# see PATCH.md phase 1 for the "why".

# Keys that only make sense for the archive path. Presence alongside a "file"
# kind is almost always a stale svc block copied from an archive preset, so it
# fails loud instead of silently being ignored.
ARCHIVE_ONLY_KEYS = ("tar", "move", "version_check", "version_stamp", "executable")


def fetch_source(prefix, settings):
    """Fetch settings["svc"]["source"] per its detected kind (fetch_kind):
    "file" downloads/compares a single script or binary in place; "archive"
    downloads into a local cache and optionally tar-extracts and/or moves it
    into install_dir, stamps its version, and ensures it's executable. Returns
    the list of pyobjects requisite references that should trigger a restart
    when they change - the dispatcher wires these into the systemd block."""

    svc = settings["svc"]
    install_dir = settings["install_dir"]
    owner = settings.get("user", {})
    sid = "_".join(prefix)

    kind = fetch_kind(svc)

    if kind == "file":
        bad = [key for key in ARCHIVE_ONLY_KEYS if key in svc]
        if bad:
            raise ValueError(
                "svc.{} only applies to kind: archive, but this instance's "
                "svc.kind is (or resolves to) 'file' - see fetch_kind in "
                "lib.py".format(bad[0]))

        # fetch_target only raises on an empty source when svc.target is unset,
        # and presets that have no release to resolve (redis_check) ship
        # source: "" with a target already set - so an operator who forgets
        # svc.source would otherwise get File.managed(source="") and a
        # confusing Salt error instead of a render-time one.
        if not svc.get("source"):
            raise ValueError(
                "svc.source is empty - a kind: file instance must set it "
                "(see the redis_check preset's header)")

        target = fetch_target(svc, install_dir)
        source_hash = svc.get("source_hash")

        # No cache hop, no move, no version_check/version_stamp:
        # File.managed compares hashes itself and reports "changed" only when
        # the content actually differs - the restart trigger we want, for both
        # https://... (re-fetched to cache each run, then compared) and
        # salt://... (fileserver-hashed) sources.
        File.managed(sid + "_file",
                     name=target,
                     source=svc["source"],
                     user="root", group="root",
                     mode=svc.get("mode", "755"),
                     makedirs=True,
                     **({"source_hash": source_hash} if source_hash else {"skip_verify": True}))
        changed = [File(sid + "_file")]
        _data_dirs(sid, svc, owner, changed)
        return changed

    # kind == "archive": today's path, unchanged - except the install_dir
    # File.directory moved out to blocks/install_dir.sls, plus version_stamp
    # and executable below.
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

    tag = svc.get("tag", svc.get("version", ""))

    tar = svc.get("tar")
    if tar is not None:
        tar = deep_format(tar, file_scope)
        command = tar_extract_command(
            archive, install_dir, args=tar.get("args", ""), unpack=tar.get("unpack", "")
        )

        extract_kwargs = dict(name=command, shell="/bin/bash", user="root", group="root",
                              require=[File(sid + "_archive")])

        # Idempotency guard: an explicit svc.version_check wins; otherwise, if
        # svc.version_stamp is set, fall back to comparing the stamp this block
        # writes below after a successful extract - a generic idempotency
        # primitive for source tarballs with no `binary --version` to
        # interrogate. With neither set, the archive re-extracts (and the
        # service restarts) every run - the documented cost of no default
        # guard. {binary} (exec's first token) and {file} are filled here, the
        # rest ({version}/{tag}/{install_dir}/...) by init.sls's expand.
        check = svc.get("version_check")
        if not check and svc.get("version_stamp"):
            check = '[ "$(cat {install_dir}/.binsvc_version 2>/dev/null)" = "{tag}" ]'.format(
                install_dir=install_dir, tag=tag)
        if check:
            binary = svc.get("exec", "").split()[0] if svc.get("exec") else ""
            extract_kwargs["unless"] = [deep_format(check, dict(file_scope, binary=binary))]

        Cmd.run(sid + "_extract", **extract_kwargs)
        changed = [Cmd(sid + "_extract")]

        if svc.get("version_stamp"):
            # onchanges (not require): the stamp is written only when the
            # extract actually ran and succeeded, so a failed extract can't
            # mark the version as installed. Not in `changed` - the extract it
            # depends on already is. Nested inside `tar is not None`: the
            # requisite below only resolves when sid + "_extract" exists.
            File.managed(sid + "_version_stamp",
                         name=install_dir + "/.binsvc_version",
                         contents=tag, user="root", group="root", mode="644",
                         onchanges=[Cmd(sid + "_extract")])
    elif svc.get("version_stamp"):
        raise ValueError(
            "svc.version_stamp requires svc.tar - there is no extract to stamp")

    move = svc.get("move")
    if move is not None:
        move = deep_format(move, file_scope)
        File.rename(sid + "_move", name=move["dst"], source=move["src"],
                    force=True, makedirs=True, require=changed)
        changed = [File(sid + "_move")]

    # Default executable is exec's first token - a Python-from-tarball
    # instance has exec: "{venv_dir}/bin/python {install_dir}/x.py", whose
    # first token doesn't exist yet at fetch time and would hard-fail the
    # chmod; such an instance sets svc.executable: false to skip it.
    executable = svc.get("executable", svc["exec"].split()[0] if svc.get("exec") else None)
    if executable:
        File.managed(sid + "_executable",
                     name=executable,
                     user="root", group="root", mode="755",
                     require=changed)

    _data_dirs(sid, svc, owner, changed)

    return changed


def _data_dirs(sid, svc, owner, changed):
    """Service-owned writable state. Emitted for *both* fetch kinds: what a
    service must be able to write into has nothing to do with how its code
    arrived, and a silently-ignored data_dirs on the "file" path would be a
    permission bug discovered at runtime instead of at render.

    Fetching runs as root (extraction with --no-same-owner), so anything the
    archive *ships* lands root-owned; dirs the service must write into (e.g.
    Grafana's data/db, plugins, logs) must be the service user's. Kept distinct
    from the root-owned program files on purpose - a compromised service can't
    rewrite its own binary. recurse fixes ownership of any contents the tarball
    shipped. Not added to `changed`: an ownership fixup isn't a "new binary"
    restart trigger. data_dirs are already concrete here (init.sls expands
    {install_dir}/... before dispatch)."""

    for index, data_dir in enumerate(svc.get("data_dirs", [])):
        File.directory(sid + "_data_dir_" + str(index),
                       name=data_dir,
                       user=owner.get("name", "root"),
                       group=owner.get("group", "root"),
                       makedirs=True,
                       recurse=["user", "group"],
                       require=changed)
