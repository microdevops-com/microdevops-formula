#!/bin/bash

cat > /etc/network/interfaces <<- EOM
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
        address $1
        netmask $2
        gateway $3
        dns-nameservers $4
        dns-search $5
EOM

[[ ! -z $8 ]] && echo "        hwaddress ether $8" >> /etc/network/interfaces

cat >> /etc/network/interfaces <<- EOM
auto eth1
iface eth1 inet static
        address $6
        netmask $7
EOM


/bin/kill -9 `/bin/ps ax | /bin/grep dhclient | /bin/grep -v grep | /usr/bin/awk '{print $1}'`
/bin/sleep 2
/bin/kill -9 `/bin/ps ax | /bin/grep dhclient | /bin/grep -v grep | /usr/bin/awk '{print $1}'`
/sbin/ifdown --force eth0
/bin/sleep 2
/sbin/ifup eth0
/bin/sleep 5
