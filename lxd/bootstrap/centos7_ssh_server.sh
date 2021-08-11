#!/bin/bash

yum -y install openssh-server
systemctl enable sshd
systemctl start sshd
