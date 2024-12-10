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
          to: 10.0.0.0/8
          via: $8
        - on-link: true
          to: 192.168.0.0/16
          via: $8
        - on-link: true
          to: 188.42.208.0/21
          via: $8
EOM

netplan apply
