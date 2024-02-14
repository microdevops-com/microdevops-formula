#!/bin/bash

mkdir -p -m 0700 /root/.ssh
if [[ ! -e /root/.ssh/authorized_keys ]]; then
	touch /root/.ssh/authorized_keys
fi

for KEY in "$@"; do
	grep "${KEY}" /root/.ssh/authorized_keys || echo "${KEY}" >> /root/.ssh/authorized_keys
done
