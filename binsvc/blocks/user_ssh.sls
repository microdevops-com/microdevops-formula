#!pyobjects
# vim: set ft=python:

# Refactored out of application/utils.py's user()/ssh() - same behavior
# (group+user, .ssh dir, keys, authorized_keys, config, known_hosts), adapted
# to the (prefix, settings) building-block calling convention and fixing the
# `group = user` self-reference bug in the original (it captured the function
# object, not the username).


def _manage_user(prefix, user):
    sid = "_".join(prefix + ["user"])
    name = user["name"]
    group = user.get("group", name)
    home = user.get("home", "/home/{}".format(name))

    Group.present(sid + "_group", name=group)

    user_kwargs = {key: value for key, value in user.items() if key not in ("manage", "name", "group", "groups")}
    user_kwargs.setdefault("home", home)
    user_kwargs.setdefault("password", "!")
    user_kwargs.setdefault("enforce_password", False)
    user_kwargs["groups"] = [group] + [g for g in user.get("groups", []) if g != group]

    User.present(sid, name=name, require=[Group(sid + "_group")], **user_kwargs)

    return name, group, home


def _manage_ssh(prefix, ssh, name, group, home):
    sid = "_".join(prefix + ["ssh"])
    ssh_dir = home.rstrip("/") + "/.ssh"
    user_id = "_".join(prefix + ["user"])

    File.directory(sid + "_dir", name=ssh_dir, user=name, group=group, mode="700",
                   require=[User(user_id)])

    for key_name, key in ssh.get("keys", {}).items():
        key_path = ssh_dir + "/" + key_name
        pubkey_path = key_path + ".pub"

        File.managed(sid + "_key_" + key_name, name=key_path, user=name, group=group, mode="600",
                     contents=key, require=[File(sid + "_dir")])
        Cmd.run(sid + "_pubkey_" + key_name,
                name="ssh-keygen -y -f {} > {}".format(key_path, pubkey_path),
                cwd=ssh_dir, runas=name,
                unless="test -s {}".format(pubkey_path),
                require=[File(sid + "_key_" + key_name)])

    if "authorized_keys" in ssh:
        File.managed(sid + "_authorized_keys",
                     name=ssh_dir + "/authorized_keys",
                     user=name, group=group, mode="600",
                     contents="\n".join(ssh["authorized_keys"]),
                     require=[File(sid + "_dir")])

    if "config" in ssh:
        File.managed(sid + "_config",
                     name=ssh_dir + "/config",
                     user=name, group=group, mode="600",
                     contents=ssh["config"],
                     require=[File(sid + "_dir")])

    if "known_hosts" in ssh:
        known = ssh["known_hosts"]
        timeout = known.get("timeout", 5)
        config = known.get("config", ssh_dir + "/known_hosts")

        for entry in known.get("hosts", []):
            host, port, *rest = entry.split(":")
            if len(rest) == 2:
                enc, key = rest
            elif len(rest) == 1:
                enc, key = rest[0], None
            else:
                enc, key = "ssh-ed25519", None

            SshKnownHosts.present(sid + "_known_{}_{}_{}".format(host, port, enc),
                                  name=host, port=port, enc=enc, key=key, config=config,
                                  user=name, hash_known_hosts=False, timeout=timeout,
                                  require=[File(sid + "_dir")])


def user_and_ssh(prefix, settings):
    """Manage the service's system user/group and (optionally) its SSH
    identity. A no-op unless `user.manage` is true - binsvc instances that run
    as root or an externally-managed user simply omit/disable this block."""

    user = settings.get("user", {})
    ssh = settings.get("ssh", {})

    if not user.get("manage", False):
        return

    name, group, home = _manage_user(prefix, user)

    if ssh:
        _manage_ssh(prefix, ssh, name, group, home)
