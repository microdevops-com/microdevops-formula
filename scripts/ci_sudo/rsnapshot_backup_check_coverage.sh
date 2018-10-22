#!/bin/bash
GRAND_EXIT=0

if [ "_$1" != "_" ]; then
	MOD=" and $1"
	MOD_SHA=$(echo "$1" | sha1sum | awk '{print $1}')
	OUT_FILE="/srv/scripts/ci_sudo/$(basename $0)_${MOD_SHA}.out"
else
	MOD=""
	OUT_FILE="/srv/scripts/ci_sudo/$(basename $0).out"
fi

rm -f ${OUT_FILE}
exec > >(tee ${OUT_FILE})
exec 2>&1

stdbuf -oL -eL echo '---'
stdbuf -oL -eL echo 'CMD: salt --force-color -t 300 -C "G@kernel:Linux'${MOD}'" state.apply rsnapshot_backup.check_coverage queue=True'
stdbuf -oL -eL salt --force-color -t 300 -C "G@kernel:Linux${MOD}" state.apply rsnapshot_backup.check_coverage queue=True || GRAND_EXIT=1

grep -q "ERROR" ${OUT_FILE} && GRAND_EXIT=1

# 50 shades of red
grep -q "\[0;31m" ${OUT_FILE} && GRAND_EXIT=1
grep -q "\[31m" ${OUT_FILE} && GRAND_EXIT=1
grep -q "\[0;1;31m" ${OUT_FILE} && GRAND_EXIT=1

exit $GRAND_EXIT
