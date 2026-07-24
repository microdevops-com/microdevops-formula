# Salt-SSH helpers

## Static Python pre-flight

`static_build_pre_flight.sh` is a controller-side `ssh_pre_flight` helper for
hosts whose system Python cannot run the project's Salt version. Salt copies
the script to the target and executes it with `/bin/sh` before constructing its
Python shim.

The helper has one responsibility: make the Microdevops static Python runtime
available at `/opt/microdevops/static-build`. It does not configure packages,
users, services, or other host settings.

The helper:

- exits immediately when the expected Python executable successfully imports
  `sys`, `spwd`, `ssl`, and `sqlite3`;
- supports Linux x86-64 targets and requires root, `tar`, and either `wget` or
  `curl` when installation is necessary;
- downloads and extracts into a temporary directory under `/opt/microdevops`;
- validates the archive layout before touching the existing installation;
- moves an existing invalid installation to a backup path, installs the
  candidate at the runtime's required fixed prefix, and rolls back if Python
  verification fails;
- cleans temporary files and fails with a nonzero status when it cannot make
  the runtime usable.

Salt must be configured with `ssh_run_pre_flight: true` so an existing Salt
thin directory does not suppress the helper. A host opts in through its
Accounting asset:

```yaml
roster_opts:
  ssh_pre_flight: /srv/formulas/microdevops-formula/scripts/salt-ssh/static_build_pre_flight.sh
  set_path: /opt/microdevops/static-build/root/bin:\$PATH
```

The backslash is required in Accounting source because roster generation
passes the value through a Bash double-quoted `echo`. The generated roster must
contain the runtime expression without that escape:

```yaml
set_path: /opt/microdevops/static-build/root/bin:$PATH
```

The current static-build project publishes one mutable archive without a
version or checksum sidecar. Therefore this minimal helper installs or repairs
the runtime but does not replace an already valid installation. Deterministic
automatic upgrades require versioned artifacts and published checksums.
