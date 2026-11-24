#!pyobjects
# vim: set ft=python:

import salt.utils.files as saltfls
from salt.fileclient import get_file_client

saltenv = config("saltenv")
if saltenv is None:
    saltenv = "base"

def get_salt_file(name, missing_ok=False):
    """Contents of a salt:// file. A missing file raises ImportError, unless
    `missing_ok`, which returns None instead (for optional files such as a
    preset that exists only as a pillar override)."""
    with get_file_client(__opts__) as client:
        state_file = client.cache_file(name, saltenv)
        if not state_file:
            if missing_ok:
                return None
            raise ImportError(f"Could not find the file '{name}'")
        with saltfls.fopen(state_file) as f:
            return f.read()
