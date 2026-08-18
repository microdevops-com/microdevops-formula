#!/bin/bash

cat > /etc/systemd/network/enp5s0.network <<- EOM
[Match]
Name=enp5s0

[Network]
Address=$1/$2
DNS=$4
Domains=$5
DHCP=no
LinkLocalAddressing=no

[Route]
Gateway=$3
GatewayOnLink=true
EOM

systemctl restart systemd-networkd
systemctl restart systemd-resolved
