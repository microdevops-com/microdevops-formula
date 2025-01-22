#!/bin/bash

cat > /etc/netplan/10-lxc.yaml <<- EOM
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      addresses:
        - $1/$2
      routes:
        - on-link: true
          to: 0.0.0.0/0
          via: $3
      nameservers:
        search: $5
        addresses: $4
EOM

netplan apply
