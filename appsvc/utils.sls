#!pyobjects
# vim: set ft=python:

import salt.utils.files as saltfls
from salt.fileclient import get_file_client

saltenv = config("saltenv")
if saltenv is None:
    saltenv = "base"

def get_salt_file(name):
    with get_file_client(__opts__) as client:
        state_file = client.cache_file(name, saltenv)
        if not state_file:
            raise ImportError(f"Could not find the file '{name}'")
        with saltfls.fopen(state_file) as f:
            return f.read()
