#!/bin/bash

apt-get -qy -o 'DPkg::Options::=--force-confold' -o 'DPkg::Options::=--force-confdef' install openssh-server

mkdir -p -m 0700 /root/.ssh

echo "$1" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
