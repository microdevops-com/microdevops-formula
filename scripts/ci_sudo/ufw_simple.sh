#!/bin/bash
GRAND_EXIT=0
rm -f /srv/scripts/ci_sudo/$(basename $0).out
exec > >(tee /srv/scripts/ci_sudo/$(basename $0).out)
exec 2>&1

stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: salt --force-color -t 1200 -C 'G@os:Ubuntu or G@os:Debian' state.apply ufw_simple.ufw_simple queue=True"
stdbuf -oL -eL salt --force-color -t 1200 -C 'G@os:Ubuntu or G@os:Debian' state.apply ufw_simple.ufw_simple queue=True

grep -q "ERROR" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1

# 50 shades of red
grep -q "\[0;31m" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1
grep -q "\[31m" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1
grep -q "\[0;1;31m" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1

exit $GRAND_EXIT
