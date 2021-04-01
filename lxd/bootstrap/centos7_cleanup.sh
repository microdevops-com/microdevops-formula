#!/bin/bash

timeout 1m bash -c 'until ping -c 1 google.com; do echo .; sleep 1; done'

yum -y update
