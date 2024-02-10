#!/bin/bash

cat > /etc/netplan/10-incus.yaml <<- EOM
network:
  version: 2
  renderer: networkd
  ethernets:
    enp5s0:
      macaddress: $6
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

chmod 600 /etc/netplan/10-incus.yaml

netplan apply
