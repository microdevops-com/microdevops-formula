#!/bin/bash

cat > /etc/netplan/10-lxc.yaml <<- EOM
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      macaddress: $5
      addresses:
        - $1/$2
      routes:
        - on-link: true
          to: 0.0.0.0/0
      nameservers:
        search: $4
        addresses: $3
EOM

chmod 600 /etc/netplan/10-lxc.yaml

netplan apply
