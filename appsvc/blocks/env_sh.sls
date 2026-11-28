#!pyobjects
# vim: set ft=python:

from salt://appsvc/lib/runtimes.py import runtime_plans


def env_sh(prefix, settings):
    """Write the generated env file that puts nvm / pyenv / tools on PATH, and
    (when a profile is configured) source it from that rc file. No-op when none
    of nvm / pyenv / tools is active. Emits states only - not part of `changed`."""
    plan = runtime_plans(settings)["env_sh"]
    if not plan:
        return
    sid = "_".join(prefix + ["env_sh"])

    File.managed(sid, name=plan["path"], contents=plan["body"], mode="644",
                 user=plan["owner"], group=plan["group"], makedirs=True)

    if plan["profile"]:
        user = settings.get("user") or {}
        user_name = user.get("name", "root")
        user_group = user.get("group", user_name)
        # Ensure the rc file exists without touching its content.
        File.managed(sid + "_profile", name=plan["profile"], replace=False,
                     user=user_name, group=user_group)
        # Prepend, NOT append: Ubuntu's stock .bashrc returns early for
        # non-interactive shells, and CI deploys run `ssh user@host '<cmd>'`
        # non-interactively - a line at the end would never be reached, so
        # node/composer would be missing from PATH exactly where deploys need them.
        File.prepend(sid + "_profile_line", name=plan["profile"], text=plan["profile_line"],
                     require=[File(sid + "_profile"), File(sid)])
