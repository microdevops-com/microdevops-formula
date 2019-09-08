#!/bin/bash

if [ "_$1" = "_" ]; then
	echo ERROR: needed args missing: use count_alive_minions MINION_NAME
	exit 1
fi

MINION_NAME=$1

salt-run manage.alived --out=json | jq '.[]|select(. == "'${MINION_NAME}'")' | wc -l
