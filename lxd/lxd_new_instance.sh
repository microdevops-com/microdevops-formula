#!/bin/bash

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
echo "Going to run: salt $MY_HN saltutil.refresh_pillar" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	salt $MY_HN saltutil.refresh_pillar
	sleep 5
fi

# Update firewall
echo
echo "Going to refresh firewall on $MY_HN to reread the file /srv/pillar/ufw_simple/vars.jinja." | ccze -A
echo "Going to run: salt $MY_HN state.apply ufw_simple.ufw_simple" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	salt $MY_HN state.apply ufw_simple.ufw_simple
fi

# Remove minion key
echo
echo "Removing the minion acceptance (otherwise profile fails) on $MY_HN." | ccze -A
echo "Going to run: salt $MY_HN cmd.shell 'salt-key -y -d $HN'" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	salt $MY_HN cmd.shell 'salt-key -y -d '$HN
fi

# Make current container symlink
echo
echo "Going to change current container pillar symlink for $LXDHOST on $MY_HN." | ccze -A
echo "Going to run: salt $MY_HN cmd.shell 'ln -svf /srv/pillar/lxd/$LXDHOST_UNDER/$HN_UNDER.sls /srv/pillar/lxd/$LXDHOST_UNDER/current_container.sls'" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	salt $MY_HN cmd.shell 'ln -svf /srv/pillar/lxd/'$LXDHOST_UNDER'/'$HN_UNDER'.sls /srv/pillar/lxd/'$LXDHOST_UNDER'/current_container.sls'
	sleep 5
fi

# Refresh pillar LXD host
echo
echo "Going to refresh pillars on $LXDHOST to reread LXD pillar files" | ccze -A
echo "Going to run: salt $LXDHOST saltutil.refresh_pillar" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	salt $LXDHOST saltutil.refresh_pillar
	sleep 5
fi

# lxd.init
echo
echo "Going to run: salt $LXDHOST state.apply lxd.init" | ccze -A
echo "It could take 10+ minutes." | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	time salt $LXDHOST state.apply lxd.init
fi

# Wait minion key comes to master
echo
echo "Waiting for minion key" | ccze -A
time until salt-key -L 2>&1 | grep -q $HN; do sleep 1; echo -n .; done
echo

# Accept minion key
echo
echo "Accepting minion key on $MY_HN." | ccze -A
echo "Going to run: salt $MY_HN cmd.shell 'salt-key -y -a $HN'" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	salt $MY_HN cmd.shell 'salt-key -y -a '$HN
fi

# Wait minion becomes alive
echo
echo "Waiting for minion becomes alive" | ccze -A
time until salt -t 5 $HN test.ping 2>&1 | grep -q True; do sleep 1; echo -n .; done
echo

# Refresh pillar minion in case of script rerun
echo
echo "Going to refresh pillars on $HN in case of this script rerun and pillar change" | ccze -A
echo "Going to run: salt $HN saltutil.refresh_pillar" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	salt $HN saltutil.refresh_pillar
	sleep 5
fi

# pkg state
echo
echo "Going to run: salt $HN state.apply cloud.pkg" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	time salt $HN state.apply cloud.pkg
fi

# high state
echo
echo "Going to run: salt $HN state.highstate" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	time salt $HN state.highstate
fi

# Ubuntu default backups
echo
echo "Going to run: salt $HN cmd.shell '/opt/sysadmws-utils/rsnapshot_backup/rsnapshot_backup.conf_ubuntu.sh'" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	salt $HN cmd.shell '/opt/sysadmws-utils/rsnapshot_backup/rsnapshot_backup.conf_ubuntu.sh'
fi

# fail2ban
echo
echo "Going to run: salt $HN cmd.shell 'cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local'" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	salt $HN cmd.shell 'cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local'
fi

# Stop container
echo
echo "We need to stop the container for the final steps" | ccze -A
echo "Going to run: salt $LXDHOST cmd.shell \"lxc stop $HN_DASH\"" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	time salt $LXDHOST cmd.shell "lxc stop $HN_DASH"
fi

# Start container
echo
echo "Alsmost done, lets start the container" | ccze -A
echo "Going to run: salt $LXDHOST cmd.shell \"lxc start $HN_DASH\"" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	time salt $LXDHOST cmd.shell "lxc start $HN_DASH"
fi

# Wait minion becomes alive
echo
echo "Waiting for minion becomes alive" | ccze -A
time until salt -t 5 $HN test.ping 2>&1 | grep -q True; do sleep 1; echo -n .; done
echo

# app.deploy state
echo
echo "Going to run: salt $HN state.apply app.deploy" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	time salt $HN state.apply app.deploy
fi

# Final info
echo
echo "All done. Don't forget to do the following:" | ccze -A
echo "- Add data backups, if needed." | ccze -A
echo "- Add some info to tickets." | ccze -A
