"""Fake pyobjects state factories for tests/test_dispatch.py.

Records every state a block emits as (module, id) -> (function, kwargs), and
lets a test check that every requisite points at a recorded state - the thing
Salt fails an apply on ("requisite not found"). Not a model of Salt beyond
that: no ordering, no execution.
"""

STATES = {}
REQUISITES = ("require", "watch", "onchanges", "onfail", "prereq", "use", "listen")


class Ref:
    def __init__(self, module, state_id):
        self.module, self.state_id = module, state_id

    def __eq__(self, other):
        return isinstance(other, Ref) and (self.module, self.state_id) == (other.module, other.state_id)

    def __hash__(self):
        return hash((self.module, self.state_id))

    def __repr__(self):
        return "{}({!r})".format(self.module, self.state_id)


class StateFactory:
    def __init__(self, module):
        self.module = module

    def __call__(self, state_id):
        return Ref(self.module, state_id)

    def __getattr__(self, function):
        def emit(state_id, **kwargs):
            key = (self.module, state_id)
            if key in STATES:
                raise AssertionError("duplicate state {}.{}".format(*key))
            STATES[key] = (function, kwargs)
        return emit


FACTORIES = {name: StateFactory(module) for name, module in {
    "File": "file", "Cmd": "cmd", "Pkg": "pkg", "User": "user", "Group": "group",
    "SshKnownHosts": "ssh_known_hosts"}.items()}


def reset():
    STATES.clear()


def dangling():
    """['<state> <requisite> -> <missing ref>', ...] for every requisite that
    names a state not emitted in this run."""
    problems = []
    for (module, state_id), (_, kwargs) in STATES.items():
        for requisite in REQUISITES:
            for ref in kwargs.get(requisite) or []:
                if (ref.module, ref.state_id) not in STATES:
                    problems.append("{}.{} {} -> {!r}".format(module, state_id, requisite, ref))
    return problems
