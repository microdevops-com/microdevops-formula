#!/bin/bash

# $1 should be $CI_COMMIT_REF_NAME
# $2 should be repository ssh URL 

if [ "_$1" = "_" ]; then 
	stdbuf -oL -eL echo 'ERROR: $1 ($CI_COMMIT_REF_NAME) is not set'
	exit 1
fi
if [ "_$2" = "_" ]; then 
	stdbuf -oL -eL echo 'ERROR: $4 ($CI_REPOSITORY_URL) is not set'
	exit 1
fi

WORK_DIR=/tmp/salt_staging/$1
mkdir -p ${WORK_DIR}
cd ${WORK_DIR} || ( stdbuf -oL -eL echo "ERROR: ${WORK_DIR} does not exist"; exit 1 )

# Use locking with timeout to align concurrent git checkouts in a line
LOCK_DIR=${WORK_DIR}/.ci.lock
LOCK_RETRIES=1
LOCK_RETRIES_MAX=60
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

# Update local repo
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: git -C ${WORK_DIR}/srv pull || git clone $2 ${WORK_DIR}/srv"
( stdbuf -oL -eL git -C ${WORK_DIR}/srv pull || stdbuf -oL -eL git clone $2 ${WORK_DIR}/srv ) || GRAND_EXIT=1
cd ${WORK_DIR}/srv || ( stdbuf -oL -eL echo "ERROR: ${WORK_DIR}/srv does not exist"; exit 1 )
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: git fetch && git checkout -B $1 origin/$1"
( stdbuf -oL -eL git fetch && stdbuf -oL -eL git checkout -B $1 origin/$1 ) || GRAND_EXIT=1
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: git submodule init"
stdbuf -oL -eL git submodule init || GRAND_EXIT=1
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: git submodule update --recursive -f --checkout"
stdbuf -oL -eL git submodule update --recursive -f --checkout || GRAND_EXIT=1
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: .githooks/post-merge"
stdbuf -oL -eL .githooks/post-merge || GRAND_EXIT=1
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: populating repo/etc/salt for salt-call --local"
( mkdir -p ${WORK_DIR}/etc/salt && rsync -av ${WORK_DIR}/srv/.gitlab-ci/staging-etc/ ${WORK_DIR}/etc/salt/ && sed -i -e "s#_WORK_DIR_#${WORK_DIR}#" ${WORK_DIR}/etc/salt/* ) || exit 1

# Check exclude file and eval grep command
if [[ -e /srv/scripts/ci_sudo/$(basename $0).exclude ]]; then
	GREP_E="-f /srv/scripts/ci_sudo/$(basename $0).exclude"
else
	GREP_E=""
fi

# Get the list of states and echo for debug
stdbuf -oL -eL echo "NOTICE: found states with grep ${GREP_E}:"
for STATE in $(salt-call --local --config-dir=${WORK_DIR}/etc/salt cp.list_states | awk '{print $2}' | grep -v -e "^top$" ${GREP_E}); do
	stdbuf -oL -eL echo "${STATE}"
done

# Get the list of states and render them
for STATE in $(salt-call --local --config-dir=${WORK_DIR}/etc/salt cp.list_states | awk '{print $2}' | grep -v -e "^top$" ${GREP_E}); do
	stdbuf -oL -eL echo "NOTICE: checking state ${STATE}"
	if stdbuf -oL -eL time salt-call --local --config-dir=${WORK_DIR}/etc/salt --retcode-passthrough state.show_sls ${STATE}; then
		stdbuf -oL -eL echo "NOTICE: state.show_sls of state ${STATE} succeeded"
	else
		GRAND_EXIT=1
		stdbuf -oL -eL echo "ERROR: state.show_sls of state ${STATE} failed"
	fi
done

grep -q "^ERROR" /srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1

exit $GRAND_EXIT
