#!/bin/bash

GRAND_EXIT=0

# Use locking with timeout to align concurrent git checkouts in a line
LOCK_DIR=/srv/.ci.lock
LOCK_RETRIES=1
LOCK_RETRIES_MAX=180
SLEEP_TIME=5
until mkdir "$LOCK_DIR" || (( LOCK_RETRIES == LOCK_RETRIES_MAX ))
do
	echo "NOTICE: Acquiring lock failed on $LOCK_DIR, sleeping for ${SLEEP_TIME}s"
	let "LOCK_RETRIES++"
	sleep ${SLEEP_TIME}
done
if [[ ${LOCK_RETRIES} -eq ${LOCK_RETRIES_MAX} ]]; then
	echo "ERROR: Cannot acquire lock after ${LOCK_RETRIES} retries, giving up on $LOCK_DIR"
	exit 1
else
	echo "NOTICE: Successfully acquired lock on $LOCK_DIR"
	trap 'rm -rf "$LOCK_DIR"' 0
fi

rm -f /srv/scripts/ci_sudo/$(basename $0).out
exec > >(tee /srv/scripts/ci_sudo/$(basename $0).out)
exec 2>&1

cd /srv || ( echo "ERROR: /srv does not exist"; exit 1 )
set -x
# https://stackoverflow.com/a/4327720
git fetch origin master || GRAND_EXIT=1
git checkout --force -B master origin/master || GRAND_EXIT=1
git reset --hard || GRAND_EXIT=1
git clean -fdx || GRAND_EXIT=1
git clean -d -f -f || GRAND_EXIT=1 # https://stackoverflow.com/a/14521765
git submodule sync || GRAND_EXIT=1 # this is needed to update the submodule URLs
git submodule update --init --recursive --force || GRAND_EXIT=1
git submodule foreach git fetch origin master || GRAND_EXIT=1
git submodule foreach git checkout --force -B master origin/master || GRAND_EXIT=1
git submodule foreach git reset --hard || GRAND_EXIT=1
git submodule foreach git clean -fdx || GRAND_EXIT=1
#
ln -sf ../../.githooks/post-merge .git/hooks/post-merge || GRAND_EXIT=1
.githooks/post-merge || GRAND_EXIT=1
#
set +x

grep -q "ERROR" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1

exit $GRAND_EXIT
