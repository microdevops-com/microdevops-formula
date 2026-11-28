"""Load appsvc's lib modules, compat.py and the pyobjects .sls files for pytest.

lib/*.py import each other with pyobjects' `from salt://appsvc/lib/<m>.py
import ...`, which plain Python cannot parse. This finder serves them as the
package `appsvc_lib` (`appsvc_lib.core`, `appsvc_lib.web`, ...), rewriting
those lines to `from appsvc_lib.<m> import ...` - the only transformation.

The `#!pyobjects` blocks and dispatch.sls are served the same way as
`appsvc_sls.<path>` (`appsvc_sls.dispatch`, `appsvc_sls.blocks.cron`), with
their `salt://` imports rewritten and the fake state factories of
tests/fake_pyobjects.py in place of the ones pyobjects injects. Salt itself
never sees this file.
"""

import importlib.abc
import importlib.util
import os
import re
import sys

APPSVC = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LIB = os.path.join(APPSVC, "lib")
PACKAGE = "appsvc_lib"
SLS_PACKAGE = "appsvc_sls"
_REWRITES = [
    (re.compile(r"^(\s*)from\s+salt://appsvc/lib/(\w+)\.py\s+import\s", re.M), r"\1from appsvc_lib.\2 import "),
    (re.compile(r"^(\s*)from\s+salt://appsvc/compat\.py\s+import\s", re.M), r"\1from compat import "),
    (re.compile(r"^(\s*)from\s+salt://appsvc/((?:\w+/)*\w+)\.sls\s+import\s", re.M),
     lambda m: "{}from {}.{} import ".format(m.group(1), SLS_PACKAGE, m.group(2).replace("/", "."))),
    (re.compile(r"^(\s*)from\s+salt\.utils\.pyobjects\s+import\s", re.M), r"\1from fake_pyobjects import "),
]


class _Loader(importlib.abc.SourceLoader):
    def __init__(self, path, sls=False):
        self.path, self.sls = path, sls

    def get_filename(self, fullname):
        return self.path

    def get_data(self, path):
        with open(path) as f:
            source = f.read()
        for pattern, replacement in _REWRITES:
            source = pattern.sub(replacement, source)
        return source.encode()

    def exec_module(self, module):
        if self.sls:
            import fake_pyobjects
            module.__dict__.update(fake_pyobjects.FACTORIES)
        super().exec_module(module)


def _package(fullname):
    return importlib.util.spec_from_loader(fullname, None, is_package=True)


class _Finder(importlib.abc.MetaPathFinder):
    def find_spec(self, fullname, path, target=None):
        if fullname in (PACKAGE, SLS_PACKAGE):
            return _package(fullname)
        if fullname.startswith(PACKAGE + "."):
            module_path = os.path.join(LIB, fullname.split(".", 1)[1] + ".py")
            if os.path.exists(module_path):
                return importlib.util.spec_from_file_location(fullname, module_path,
                                                              loader=_Loader(module_path))
        if fullname.startswith(SLS_PACKAGE + "."):
            rel = fullname.split(".", 1)[1].replace(".", os.sep)
            if os.path.isdir(os.path.join(APPSVC, rel)):
                return _package(fullname)
            module_path = os.path.join(APPSVC, rel + ".sls")
            if os.path.exists(module_path):
                return importlib.util.spec_from_file_location(fullname, module_path,
                                                              loader=_Loader(module_path, sls=True))
        return None


sys.meta_path.insert(0, _Finder())
sys.path.insert(0, APPSVC)  # compat.py
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # fake_pyobjects
