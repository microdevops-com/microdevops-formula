#!/bin/bash

if [ "_$1" = "_" ]; then
	echo ERROR: needed args missing: use count_alive_minions.sh MINION_NAME
	exit 1
fi

MINION_NAME=$1

salt-run manage.up timeout=20 gather_job_timeout=30 --out=json | jq '.[]|select(. == "'${MINION_NAME}'")' | wc -l
