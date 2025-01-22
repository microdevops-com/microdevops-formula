#!/bin/bash

cat > /etc/netplan/10-lxc.yaml <<- EOM
network:
  version: 2
  renderer: networkd
  ethernets:
    enp5s0:
      addresses:
        - $1/$2
      routes:
        - on-link: true
          to: 0.0.0.0/0
          via: $3
      nameservers:
        search: $5
        addresses: $4
    enp6s0:
      addresses:
        - $6/$7
      routes:
        - on-link: true
          to: $8
          via: $9
EOM

netplan apply
