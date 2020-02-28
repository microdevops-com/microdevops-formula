#!/bin/bash
GRAND_EXIT=0

if [ "_$1" = "_" ]; then
	echo ERROR: needed args missing: use rsnapshot_backup_check_coverage.sh TARGET
	exit 1
fi

TARGET=$1
# Check port in TARGET
if echo ${TARGET} | grep -q :; then
	TARGET=$(echo ${TARGET} | awk -F: '{print $1}')
fi
	
OUT_FILE="/srv/scripts/ci_sudo/$(basename $0)_${TARGET}.out"

rm -f ${OUT_FILE}
exec > >(tee ${OUT_FILE})
exec 2>&1

stdbuf -oL -eL echo ---
stdbuf -oL -eL echo CMD: salt --force-color -t 300 ${TARGET} state.apply rsnapshot_backup.check_coverage queue=True
stdbuf -oL -eL  bash -c "salt --force-color -t 300 ${TARGET} state.apply rsnapshot_backup.check_coverage queue=True" || GRAND_EXIT=1

# Check out file for errors
grep -q "ERROR" ${OUT_FILE} && GRAND_EXIT=1

# Check out file for red color with shades 
grep -q "\[0;31m" ${OUT_FILE} && GRAND_EXIT=1
grep -q "\[31m" ${OUT_FILE} && GRAND_EXIT=1
grep -q "\[0;1;31m" ${OUT_FILE} && GRAND_EXIT=1

exit $GRAND_EXIT
