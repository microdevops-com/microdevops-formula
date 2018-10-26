#!/bin/bash

/bin/yum install https://repo.saltstack.com/yum/redhat/salt-repo-latest-2.el6.noarch.rpm
/bin/yum clean expire-cache
/bin/yum install salt-minion
/bin/rm -f /etc/salt/minion_id
/bin/cp /etc/hostname /etc/salt/minion_id
echo "fqdn: $(cat /etc/salt/minion_id)" >> /etc/salt/grains
/bin/sed -i.bak -e "s/#master: salt/master:\n  - $1/" /etc/salt/minion
/sbin/service salt-minion restart
