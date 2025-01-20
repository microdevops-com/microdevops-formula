#!/bin/bash

cat > /etc/systemd/network/eth0.network <<- EOM
[Match]
Name=eth0

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
