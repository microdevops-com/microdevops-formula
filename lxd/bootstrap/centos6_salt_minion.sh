#!/bin/bash

/usr/bin/yum -t -q -y install https://repo.saltstack.com/yum/redhat/salt-repo-latest-2.el6.noarch.rpm
/usr/bin/yum -t -q -y clean expire-cache
/usr/bin/yum -t -q -y install salt-minion
/bin/rm -f /etc/salt/minion_id
/bin/cp /etc/hostname /etc/salt/minion_id
echo "fqdn: $(cat /etc/salt/minion_id)" >> /etc/salt/grains
/bin/sed -i.bak -e "s/#master: salt/master:\n  - $1/" /etc/salt/minion
/sbin/service salt-minion restart
/sbin/chkconfig --add salt-minion
