#!/bin/bash

cat > /etc/sysconfig/network-scripts/ifcfg-eth0 <<- EOM
DEVICE=eth0
ONBOOT=yes
TYPE=Ethernet
BOOTPROTO=static
NAME="System eth0"
IPADDR=$2
NETMASK=$3
NM_CONTROLLED=no
EOM

[[ ! -z $7 ]] && echo "HWADDR=$7" >> /etc/sysconfig/network-scripts/ifcfg-eth0

cat > /etc/sysconfig/network <<- EOM
NETWORKING=yes
HOSTNAME=$1
GATEWAY=$4
EOM

echo "search $6" > /etc/resolv.conf
for NS in $5; do echo "nameserver ${NS}" >> /etc/resolv.conf; done

/etc/init.d/network restart
/bin/sleep 5
