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

# Wait dbus to be available
timeout 30s bash -c 'until [[ -n $DBUS_SESSION_BUS_ADDRESS1 ]]; do echo -n .; sleep 1; done'

systemctl restart systemd-networkd
systemctl restart systemd-resolved
