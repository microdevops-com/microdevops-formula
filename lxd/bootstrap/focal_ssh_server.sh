#!/bin/bash

apt-get -qy -o 'DPkg::Options::=--force-confold' -o 'DPkg::Options::=--force-confdef' install openssh-server
