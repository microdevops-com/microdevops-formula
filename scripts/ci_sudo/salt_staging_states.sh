#!/bin/bash
set -x

cd /srv || ( stdbuf -oL -eL echo "ERROR: /srv does not exist"; exit 1 )

# $1 should be $CI_COMMIT_REF_NAME
# $2 should be target minion name

if [ "_$1" = "_" ]; then
	stdbuf -oL -eL echo 'ERROR: $1 ($CI_COMMIT_REF_NAME) is not set'
	exit 1
fi
if [ "_$2" = "_" ]; then
	stdbuf -oL -eL echo 'ERROR: $2 (target minion name) is not set'
	exit 1
fi

# Use locking with timeout to align concurrent git checkouts in a line
LOCK_DIR=/srv/.ci.lock
LOCK_RETRIES=1
LOCK_RETRIES_MAX=180
SLEEP_TIME=5
until mkdir "$LOCK_DIR" || (( LOCK_RETRIES == LOCK_RETRIES_MAX ))
do
	stdbuf -oL -eL echo "NOTICE: Acquiring lock failed on $LOCK_DIR, sleeping for ${SLEEP_TIME}s"
	let "LOCK_RETRIES++"
	sleep ${SLEEP_TIME}
done
if [ ${LOCK_RETRIES} -eq ${LOCK_RETRIES_MAX} ]; then
	stdbuf -oL -eL echo "ERROR: Cannot acquire lock after ${LOCK_RETRIES} retries, giving up on $LOCK_DIR"
	exit 1
else
	stdbuf -oL -eL echo "NOTICE: Successfully acquired lock on $LOCK_DIR"
	trap 'rm -rf "$LOCK_DIR"' 0
fi

GRAND_EXIT=0
rm -f /srv/scripts/ci_sudo/$(basename $0).out
exec > >(tee /srv/scripts/ci_sudo/$(basename $0).out)
exec 2>&1

stdbuf -oL -eL echo "---"
( cd /srv && stdbuf -oL -eL git pull --ff-only && stdbuf -oL -eL git checkout -B $1 origin/$1) || GRAND_EXIT=1
stdbuf -oL -eL echo "---"
( cd /srv && stdbuf -oL -eL git submodule update --recursive -f --checkout ) || GRAND_EXIT=1
stdbuf -oL -eL echo "---"
( cd /srv && stdbuf -oL -eL ln -sf ../../.githooks/post-merge .git/hooks/post-merge ) || GRAND_EXIT=1
stdbuf -oL -eL echo "---"
( cd /srv && stdbuf -oL -eL .githooks/post-merge ) || GRAND_EXIT=1

# Run app.deploy
stdbuf -oL -eL echo "---"
stdbuf -oL -eL salt --force-color -t 300 $2 state.apply cloud.pkg || GRAND_EXIT=1
# Run highstate
stdbuf -oL -eL echo "---"
stdbuf -oL -eL salt --force-color -t 300 $2 state.highstate || GRAND_EXIT=1
# Run app.deploy
stdbuf -oL -eL echo "---"
stdbuf -oL -eL salt --force-color -t 300 $2 state.apply app.deploy || GRAND_EXIT=1

grep -q "ERROR" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1

# 50 shades of red
grep -q "\[0;31m" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1
grep -q "\[31m" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1
grep -q "\[0;1;31m" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1

exit $GRAND_EXIT
