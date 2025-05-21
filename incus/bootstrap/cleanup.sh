#!/bin/bash

[[ -d /home/ubuntu ]] && userdel -r "ubuntu"
[[ -d /home/debian ]] && userdel -r "debian"
rm -f /etc/sudoers.d/90-incus

timeout 1m bash -c 'until ping -c 1 google.com; do echo .; sleep 1; done'

apt-get update
apt-get -qy -o 'DPkg::Options::=--force-confold' -o 'DPkg::Options::=--force-confdef' upgrade
apt-get -qy -o 'DPkg::Options::=--force-confold' -o 'DPkg::Options::=--force-confdef' dist-upgrade

echo "Set disable_coredump false" >> /etc/sudo.conf
