#!pyobjects
# vim: set ft=python:

from salt://binsvc/lib.py import render_config, deep_format

# Renders the instance's config file(s) from `settings["config"]`, a dict of
# named entries each describing one file. The entry's key is available as
# `{confname}` within the entry, so a filename can be declared once (as the key)
# instead of repeated in `name`:
#
#   config:
#     custom.ini:                          # {confname} == "custom.ini"
#       name: "{install_dir}/conf/{confname}"
#       format: ini                        # optional: yaml (default), ini, json
#       contents: {server: {http_port: 3000}}  # dict/list -> rendered via format; strings used verbatim
#     extra:
#       name: "{install_dir}/extra.conf"
#       source: salt://my-formula/files/extra.conf.jinja
#       template: jinja
#
# This deliberately stays narrower than _include/file_manager - it covers the
# common "one or two managed files per instance" case; reach for a `files`
# block calling into file_manager directly if an instance needs more.


def config_files(prefix, settings):
    """Render the instance's config file(s). Returns the list of pyobjects
    requisite references that should trigger a restart when they change."""

    config = settings.get("config", {})
    owner = settings.get("user", {})
    sid = "_".join(prefix + ["config"])
    changed = []

    for key, item in config.items():
        if not isinstance(item, dict) or "name" not in item:
            continue

        # {confname} = this entry's key; narrow late expansion (like
        # fetch_archive's {file}), so the filename lives in one place. Other
        # placeholders are already resolved by init.sls and left untouched.
        item = deep_format(item, {"confname": key})

        item_id = "{}_{}".format(sid, key)
        kwargs = dict(name=item["name"],
                      user=item.get("user", owner.get("name", "root")),
                      group=item.get("group", owner.get("group", "root")),
                      mode=item.get("mode", "644"),
                      makedirs=item.get("makedirs", True))

        if "source" in item:
            kwargs["source"] = item["source"]
            kwargs["template"] = item.get("template", "jinja")
        elif "contents" in item:
            contents = item["contents"]
            if isinstance(contents, (dict, list)):
                contents = render_config(contents, item.get("format", "yaml"))
            kwargs["contents"] = contents

        File.managed(item_id, **kwargs)
        changed.append(File(item_id))

    return changed
