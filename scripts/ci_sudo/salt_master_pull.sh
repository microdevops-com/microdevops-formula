#!/bin/bash
GRAND_EXIT=0
rm -f /srv/scripts/ci_sudo/$(basename $0).out
exec > >(tee /srv/scripts/ci_sudo/$(basename $0).out)
exec 2>&1

stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: cd /srv && git pull --ff-only"
( cd /srv && stdbuf -oL -eL git pull ) || GRAND_EXIT=1
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: cd /srv && git submodule update --recursive -f --checkout"
( cd /srv && stdbuf -oL -eL git submodule update --recursive -f --checkout ) || GRAND_EXIT=1
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: cd /srv && .githooks/post-merge"
( cd /srv && stdbuf -oL -eL .githooks/post-merge ) || GRAND_EXIT=1

grep -q "ERROR" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1

exit $GRAND_EXIT
