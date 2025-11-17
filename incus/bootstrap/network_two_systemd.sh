#!/bin/bash

cat > /etc/systemd/network/eth0.network <<EOF
[Match]
Name=eth0

[Network]
Address=$1/$2
DNS=$4
Domains=$5
DHCP=no
LinkLocalAddressing=no

[Route]
Destination=0.0.0.0/0
Gateway=$3
GatewayOnLink=yes
EOF

cat > /etc/systemd/network/eth1.network <<EOF
[Match]
Name=eth1

[Network]
Address=$6/$7
DHCP=no
LinkLocalAddressing=no
EOF

systemctl restart systemd-networkd
systemctl restart systemd-resolved
