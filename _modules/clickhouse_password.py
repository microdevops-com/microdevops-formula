"""
Password hashing helper for the clickhouse_users formula.
"""

import hashlib


def double_sha1_hex(password):
    if password is None:
        password = ""
    first_digest = hashlib.sha1(password.encode("utf-8")).digest()
    return hashlib.sha1(first_digest).hexdigest()
