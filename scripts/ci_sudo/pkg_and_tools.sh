#!/bin/bash
GRAND_EXIT=0
rm -f /srv/scripts/ci_sudo/$(basename $0).out
exec > >(tee /srv/scripts/ci_sudo/$(basename $0).out)
exec 2>&1

( set -x ; stdbuf -oL -eL salt --force-color -t 300 -C 'G@kernel:Linux' state.apply pkg.pkg queue=True ) || GRAND_EXIT=1
( set -x ; stdbuf -oL -eL salt --force-color -t 300 -C 'G@kernel:Linux' state.apply netdata.netdata queue=True ) || GRAND_EXIT=1
( set -x ; stdbuf -oL -eL salt --force-color -t 300 -C 'G@os:Ubuntu or G@os:Debian' state.apply bash.bash_completions queue=True ) || GRAND_EXIT=1
( set -x ; stdbuf -oL -eL salt --force-color -t 300 -C 'G@os:Ubuntu or G@os:Debian' state.apply bash.bash_misc queue=True ) || GRAND_EXIT=1
( set -x ; stdbuf -oL -eL salt --force-color -t 300 -C 'G@kernel:Linux' state.apply vim.vim queue=True ) || GRAND_EXIT=1
( set -x ; stdbuf -oL -eL salt --force-color -t 300 -C 'G@kernel:Linux' state.apply ntp.ntp queue=True ) || GRAND_EXIT=1

grep -q "ERROR" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1

# 50 shades of red
grep -q "\[0;31m" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1
grep -q "\[31m" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1
grep -q "\[0;1;31m" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1

exit $GRAND_EXIT
