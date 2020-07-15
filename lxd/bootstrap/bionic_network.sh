#!/bin/bash

/bin/rm -f /etc/netplan/10-lxc.yaml

/sbin/ip address replace $1/$2 dev eth0
/sbin/ip route replace default via $3

/bin/systemctl disable --now systemd-networkd.socket systemd-networkd systemd-networkd-wait-online systemd-resolved
/bin/systemctl mask          systemd-networkd.socket systemd-networkd systemd-networkd-wait-online systemd-resolved

sleep 2
echo "search $5" > /etc/resolv.conf
for NS in $4; do echo "nameserver ${NS}" >> /etc/resolv.conf; done

/usr/bin/apt-get -qy -o 'DPkg::Options::=--force-confold' -o 'DPkg::Options::=--force-confdef' install ifupdown resolvconf net-tools

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

[[ ! -z $6 ]] && echo "  hwaddress ether $6" >> /etc/network/interfaces

/bin/kill -9 `/bin/ps ax | /bin/grep dhclient | /bin/grep -v grep | /usr/bin/awk '{print $1}'`
/bin/sleep 2
/bin/kill -9 `/bin/ps ax | /bin/grep dhclient | /bin/grep -v grep | /usr/bin/awk '{print $1}'`
/sbin/ifdown --force eth0
/bin/sleep 2
/sbin/ifup eth0
/bin/sleep 5
/bin/systemctl unmask networking
/bin/systemctl enable networking
/bin/systemctl restart networking
/usr/bin/apt-get -qy purge nplan netplan.io
