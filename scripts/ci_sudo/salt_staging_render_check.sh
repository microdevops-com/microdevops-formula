#!/bin/bash

# $1 should be $CI_COMMIT_REF_NAME
# $2 should be $CI_COMMIT_SHA
# $3 should be $CI_COMMIT_BEFORE_SHA

cd /srv || ( stdbuf -oL -eL echo "ERROR: /srv does not exist"; exit 1 )

GRAND_EXIT=0
rm -f /srv/scripts/ci_sudo/$(basename $0).out
exec > >(tee /srv/scripts/ci_sudo/$(basename $0).out)
exec 2>&1

# Staging environment is not concurrent.
# Place a lock and or wait until previous lock or timeout.
# We are waiting for a lock because we do not want to fail test if staging is already locked.
LOCK_DIR=/srv/.ci.lock
LOCK_RETRIES=1
LOCK_RETRIES_MAX=120
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

# Update local repo to commit
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: git fetch && git checkout -B $1 origin/$1"
( stdbuf -oL -eL git fetch && stdbuf -oL -eL git checkout -B $1 origin/$1 ) || GRAND_EXIT=1
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: git submodule update --recursive -f --checkout"
( stdbuf -oL -eL git submodule update --recursive -f --checkout ) || GRAND_EXIT=1
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: .githooks/post-merge"
( stdbuf -oL -eL .githooks/post-merge ) || GRAND_EXIT=1

# Get changed files from the last push
for FILE in $(git diff-tree --no-commit-id --name-only -r $2 $3); do
	stdbuf -oL -eL echo "NOTICE: checking file $FILE"
done

grep -q "ERROR" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1

exit $GRAND_EXIT
