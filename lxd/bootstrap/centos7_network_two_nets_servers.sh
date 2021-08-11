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

cat > /etc/sysconfig/network-scripts/ifcfg-eth1 <<- EOM
DEVICE=eth1
ONBOOT=yes
TYPE=Ethernet
BOOTPROTO=static
NAME="System eth1"
IPADDR=$6
NETMASK=$7
NM_CONTROLLED=no
EOM

cat > /etc/sysconfig/network-scripts/route-eth1 <<- EOM
10.0.0.0/8 via $8 dev eth1
192.168.0.0/16 via $8 dev eth1
188.42.208.0/21 via $8 dev eth1
EOM

cat > /etc/sysconfig/network <<- EOM
NETWORKING=yes
HOSTNAME=$9
GATEWAY=$3
EOM

echo "search $5" > /etc/resolv.conf
for NS in $4; do echo "nameserver ${NS}" >> /etc/resolv.conf; done

/etc/init.d/network restart
/bin/sleep 5
