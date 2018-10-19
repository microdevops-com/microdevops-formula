#!/bin/bash
GRAND_EXIT=0
rm -f /srv/scripts/ci_sudo/$(basename $0).out
exec > >(tee /srv/scripts/ci_sudo/$(basename $0).out)
exec 2>&1

stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: salt --force-color -t 300 -C 'G@kernel:Linux' state.apply pkg.pkg"
stdbuf -oL -eL salt --force-color -t 300 -C 'G@kernel:Linux' state.apply pkg.pkg
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: salt --force-color -t 300 -C 'G@kernel:Linux' state.apply netdata.netdata"
stdbuf -oL -eL salt --force-color -t 300 -C 'G@kernel:Linux' state.apply netdata.netdata
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: salt --force-color -t 300 -C 'G@os:Ubuntu or G@os:Debian' state.apply bash.bash_completions"
stdbuf -oL -eL salt --force-color -t 300 -C 'G@os:Ubuntu or G@os:Debian' state.apply bash.bash_completions
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: salt --force-color -t 300 -C 'G@os:Ubuntu or G@os:Debian' state.apply bash.bash_misc"
stdbuf -oL -eL salt --force-color -t 300 -C 'G@os:Ubuntu or G@os:Debian' state.apply bash.bash_misc
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: salt --force-color -t 300 -C 'G@kernel:Linux' state.apply vim.vim"
stdbuf -oL -eL salt --force-color -t 300 -C 'G@kernel:Linux' state.apply vim.vim
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: salt --force-color -t 300 -C 'G@kernel:Linux' state.apply ntp.ntp"
stdbuf -oL -eL salt --force-color -t 300 -C 'G@kernel:Linux' state.apply ntp.ntp

grep -q "ERROR" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1

# 50 shades of red
grep -q "\[0;31m" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1
grep -q "\[31m" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1
grep -q "\[0;1;31m" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1

exit $GRAND_EXIT
