"""Load appsvc's lib modules (and compat.py) for plain pytest.

lib/*.py import each other with pyobjects' `from salt://appsvc/lib/<m>.py
import ...`, which plain Python cannot parse. This finder serves them as the
package `appsvc_lib` (`appsvc_lib.core`, `appsvc_lib.web`, ...), rewriting
those lines to `from appsvc_lib.<m> import ...` - the only transformation.
Salt itself never sees this file.
"""

import importlib.abc
import importlib.util
import os
import re
import sys

APPSVC = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LIB = os.path.join(APPSVC, "lib")
PACKAGE = "appsvc_lib"
_SALT_IMPORT = re.compile(r"^(\s*)from\s+salt://appsvc/lib/(\w+)\.py\s+import\s", re.M)


class _Loader(importlib.abc.SourceLoader):
    def __init__(self, path):
        self.path = path

    def get_filename(self, fullname):
        return self.path

    def get_data(self, path):
        with open(path) as f:
            source = f.read()
        return _SALT_IMPORT.sub(r"\1from {}.\2 import ".format(PACKAGE), source).encode()


class _Finder(importlib.abc.MetaPathFinder):
    def find_spec(self, fullname, path, target=None):
        if fullname == PACKAGE:
            return importlib.util.spec_from_loader(fullname, None, is_package=True)
        if fullname.startswith(PACKAGE + "."):
            module_path = os.path.join(LIB, fullname.split(".", 1)[1] + ".py")
            if os.path.exists(module_path):
                return importlib.util.spec_from_file_location(fullname, module_path,
                                                              loader=_Loader(module_path))
        return None


sys.meta_path.insert(0, _Finder())
sys.path.insert(0, APPSVC)  # compat.py
