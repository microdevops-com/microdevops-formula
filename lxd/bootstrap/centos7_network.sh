#!/bin/bash

cat > /etc/sysconfig/network-scripts/ifcfg-eth0 <<- EOM
DEVICE=eth0
ONBOOT=yes
TYPE=Ethernet
BOOTPROTO=static
NAME="System eth0"
IPADDR=$1
NETMASK=$2
NM_CONTROLLED=no
EOM

[[ ! -z $7 ]] && echo "HWADDR=$7" >> /etc/sysconfig/network-scripts/ifcfg-eth0

cat > /etc/sysconfig/network <<- EOM
NETWORKING=yes
HOSTNAME=$6
GATEWAY=$3
EOM

echo "search $5" > /etc/resolv.conf
for NS in $4; do echo "nameserver ${NS}" >> /etc/resolv.conf; done

/etc/init.d/network restart
/bin/sleep 5
