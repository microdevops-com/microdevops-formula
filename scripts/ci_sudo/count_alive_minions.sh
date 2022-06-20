#!/bin/bash

if [[ "_$1" == "_" ]]; then
	echo ERROR: needed args missing: use count_alive_minions.sh MINION_NAME
	exit 1
fi

MINION_NAME=$1

# manage.alived works up to 2 secs but does not show windows minions for instance
# manage.up works sometimes up to 20 secs, but show windows minions, better to use this func with pipeline cache
# https://github.com/saltstack/salt/issues/58592
#salt-run manage.alived --out=json | jq '.[]|select(. == "'${MINION_NAME}'")' | wc -l
salt-run manage.up --out=json | jq '.[]|select(. == "'${MINION_NAME}'")' | wc -l
