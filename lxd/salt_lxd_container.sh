#!/bin/bash
set -e

# Get variables
MY_HN=`hostname -f`
HN=$1
LXDHOST=$2
HN_UNDER=`echo "$1" | sed -e 's/\./_/g'`
HN_DASH=`echo "$1" | sed -e 's/\./-/g'`
LXDHOST_UNDER=`echo "$2" | sed -e 's/\./_/g'`

# Some checks and info
if [[ "_$1" = "_" ]]; then
	echo "First agrument missing, you should provide new instance hostname as first argument."
	exit
fi
if [[ "_$2" = "_" ]]; then
	echo "Second agrument missing, you should provide new instance LXD hostname as second argument."
	exit
fi
echo "By now you should have done:" | ccze -A
echo "- Allocate IPs for the container ($MY_HN:/srv/pillar/ip/*.jinja)" | ccze -A
echo "- Add IP from which the minion will connect to salt servers ($MY_HN:/srv/pillar/ufw_simple/vars.jinja All_Servers array)" | ccze -A
echo "- Remove any existing instances of $HN" | ccze -A
echo "- Remove any existing additional logical volumes of $HN" | ccze -A
echo "- Inventory info in /srv/pillar/inventory/$HN_UNDER.sls and /srv/pillar/top.sls" | ccze -A
echo "- LXD container info in /srv/pillar/lxd/some_lxd_host.sls" | ccze -A

# Refresh pillar salt master
echo
echo "Going to refresh pillars on $MY_HN to reread pillar files" | ccze -A
read -ep "Are we OK with that? "
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	( set -x ; salt $MY_HN saltutil.refresh_pillar )
	sleep 5
fi

# Update firewall
echo
echo "Going to refresh firewall on $MY_HN to reread the file /srv/pillar/ufw_simple/vars.jinja." | ccze -A
read -ep "Are we OK with that? "
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	( set -x ; salt $MY_HN state.apply ufw_simple.ufw_simple queue=True )
fi

# Remove minion key
echo
echo "Removing the minion acceptance (otherwise profile fails) on $MY_HN." | ccze -A
read -ep "Are we OK with that? "
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	( set -x ; salt $MY_HN cmd.shell 'salt-key -y -d '$HN )
fi

# Refresh pillar LXD host
echo
echo "Going to refresh pillars on $LXDHOST to reread LXD pillar files" | ccze -A
read -ep "Are we OK with that? "
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	( set -x ;  salt $LXDHOST saltutil.refresh_pillar )
	sleep 5
fi

# lxd.init
echo
echo "Going to launch container $HN on host $LXDHOST" | ccze -A
read -ep "Are we OK with that? "
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	( set -x ; time salt $LXDHOST state.apply lxd.containers pillar='{lxd: {only: {"'$HN'"}, allow_stop_start: True}}' queue=True )
fi

# Wait minion key comes to master
echo
echo "Waiting for minion key" | ccze -A
time until salt-key -L 2>&1 | grep -q $HN; do sleep 1; echo -n .; done
sleep 5
echo

# Accept minion key
echo
echo "Accepting minion key on $MY_HN." | ccze -A
read -ep "Are we OK with that? "
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	( set -x ; salt $MY_HN cmd.shell 'salt-key -y -a '$HN )
fi

# Waiting for the minion to be alive
echo
echo "Waiting for the minion to be alive" | ccze -A
time until salt -t 5 $HN test.ping 2>&1 | grep -q True; do sleep 1; echo -n .; done
echo

# Refresh pillar minion in case of script rerun
echo
echo "Going to refresh pillars on $HN in case of this script rerun and pillar change" | ccze -A
read -ep "Are we OK with that? "
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	( set -x ; salt $HN saltutil.refresh_pillar )
	sleep 5
fi

# bootstrap state
echo
echo "Going to apply bootstrap" | ccze -A
read -ep "Are we OK with that? "
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	( set -x ; time salt $HN state.apply bootstrap )
fi

# bootstrap test state
echo
echo "Going to apply bootstrap" | ccze -A
read -ep "Are we OK with that? "
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	( set -x ; time salt $HN state.apply bootstrap.test )
fi

# high state
echo
echo "Going to apply highstate" | ccze -A
read -ep "Are we OK with that? "
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	( set -x ; time salt -t 600 $HN state.highstate )
fi

# Stop container
echo
echo "We need to stop the container for the final steps" | ccze -A
read -ep "Are we OK with that? "
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	( set -x ; time salt $LXDHOST cmd.shell "lxc stop $HN_DASH" )
	sleep 10
fi

# Start container
echo
echo "Alsmost done, lets start the container" | ccze -A
read -ep "Are we OK with that? "
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	( set -x ; time salt $LXDHOST cmd.shell "lxc start $HN_DASH" )
fi

# Waiting for the minion to be alive
echo
echo "Waiting for the minion to be alive" | ccze -A
time until salt -t 5 $HN test.ping 2>&1 | grep -q True; do sleep 1; echo -n .; done
echo

# app.deploy state
echo
echo "Going to apply app.deploy" | ccze -A
read -ep "Are we OK with that? "
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	( set -x ; time salt -t 600 $HN state.apply app.deploy )
fi

# Final info
echo
echo "All done. Don't forget to do the following:" | ccze -A
echo "- Add data backups, if needed." | ccze -A
echo "- Add some info to tickets." | ccze -A
