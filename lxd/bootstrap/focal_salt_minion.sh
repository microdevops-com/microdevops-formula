#!/bin/bash

timeout 1m bash -c 'until ping -c 1 google.com; do echo .; sleep 1; done'

apt-get -qy -o 'DPkg::Options::=--force-confold' -o 'DPkg::Options::=--force-confdef' install wget gnupg
echo "deb http://repo.saltstack.com/py3/ubuntu/$(lsb_release -sr)/amd64/$2 $(lsb_release -sc) main">> /etc/apt/sources.list.d/saltstack.list
wget -qO - https://repo.saltstack.com/py3/ubuntu/$(lsb_release -sr)/amd64/$2/SALTSTACK-GPG-KEY.pub | apt-key add -

[[ -d /home/ubuntu ]] && userdel -r "ubuntu"

apt-get update
apt-get -qy -o 'DPkg::Options::=--force-confold' -o 'DPkg::Options::=--force-confdef' upgrade
apt-get -qy -o 'DPkg::Options::=--force-confold' -o 'DPkg::Options::=--force-confdef' dist-upgrade

apt-get -qy -o 'DPkg::Options::=--force-confold' -o 'DPkg::Options::=--force-confdef' install salt-minion

rm -f /etc/salt/minion_id
cp /etc/hostname /etc/salt/minion_id

cat > /etc/salt/minion <<- EOM
master:
  - $1
grains:
  fqdn: $(cat /etc/salt/minion_id)
EOM

service salt-minion restart
