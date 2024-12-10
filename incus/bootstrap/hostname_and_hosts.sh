#!/bin/bash

cat > /etc/hosts <<- EOM
# IPv4
127.0.0.1 localhost.localdomain localhost
$2 $1 ${1%%.*}

# IPv6
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters

# Salt
$4 $3
$6 $5
EOM

cat > /etc/hostname <<- EOM
$1
EOM

hostname $(cat /etc/hostname)
