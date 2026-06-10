#!/bin/bash

cat > /etc/systemd/network/enp5s0.network <<- EOM
[Match]
MACAddress=$6

[Network]
Address=$1/$2
Gateway=$3
DNS=$4
Domains=$5
DHCP=no
LinkLocalAddressing=ipv4
EOM

systemctl restart systemd-networkd
systemctl restart systemd-resolved
