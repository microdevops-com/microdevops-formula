#!/bin/bash

# Get variables
MY_HN=`hostname -f`
HN=$1
HN_UNDER=`echo "$1" | sed -e 's/\./_/g'`

# Get some more vars from config
if [[ -f /srv/salt/cloud/cloud_new_instance.conf ]]; then
	. /srv/salt/cloud/cloud_new_instance.conf
fi 

# Some checks and info
if [[ "_$1" = "_" ]]; then
	echo "First agrument missing, you should provide new instance hostname as first argument."
	exit
fi
echo "By now you should have done:" | ccze -A
echo "- Allocate IP for the container ($MY_HN:/srv/pillar/ip/ip.jinja IP_192_168_100 array)" | ccze -A
echo "- Add IP from which the minion will connect to salt servers ($MY_HN:/srv/pillar/ufw_simple/vars.jinja All_Servers array)" | ccze -A
echo "- Remove any existing instances of $HN" | ccze -A
echo "- Remove any existing additional logical volumes of $HN" | ccze -A
echo "- Inventory info in /srv/pillar/inventory/$HN_UNDER.sls and /srv/pillar/top.sls" | ccze -A
echo "- Cloud info in /srv/pillar/cloud/providers.sls and /srv/pillar/cloud/profiles/$HN_UNDER.sls and /srv/pillar/cloud/profiles/init.sls" | ccze -A

# Refresh pillar
echo
echo "Going to refresh pillars on $MY_HN to reread file /srv/pillar/cloud/providers.sls and /srv/pillar/cloud/profiles/$HN_UNDER.sls and /srv/pillar/cloud/profiles/init.sls." | ccze -A
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

# Get some config vars
HN_IP=`salt --out newline_values_only $MY_HN pillar.get cloud:profiles:$HN_UNDER:network_profile:eth0:ipv4 | sed -e 's#/.*##'`
VETH_PAIR_ETH0=`salt --out newline_values_only $MY_HN pillar.get cloud:profiles:$HN_UNDER:lxc_post_profile:net_veth_pair_name:eth0`
VETH_PAIR_ETH1=`salt --out newline_values_only $MY_HN pillar.get cloud:profiles:$HN_UNDER:lxc_post_profile:net_veth_pair_name:eth1`
VETH_PAIR_ETH2=`salt --out newline_values_only $MY_HN pillar.get cloud:profiles:$HN_UNDER:lxc_post_profile:net_veth_pair_name:eth1`
ROOT_VGNAME=`salt --out newline_values_only $MY_HN pillar.get cloud:profiles:$HN_UNDER:lxc_profile:vgname`
ROOT_RESIZE=`salt --out newline_values_only $MY_HN pillar.get cloud:profiles:$HN_UNDER:lxc_post_profile:lvm_root_resize`
declare -A LVM_ADD_MOUNT
declare -A LVM_ADD_VGNAME
declare -A LVM_ADD_LVNAME
declare -A LVM_ADD_SIZE
for LVM_NUM in 1 2 3 4 5 6 7 8 9; do
	TMP_OUT=`salt --out newline_values_only $MY_HN pillar.get cloud:profiles:$HN_UNDER:lxc_post_profile:lvm_add_$LVM_NUM`
	if [[ ! -z $TMP_OUT ]]; then
		LVM_ADD_MOUNT[$LVM_NUM]=`salt --out newline_values_only $MY_HN pillar.get cloud:profiles:$HN_UNDER:lxc_post_profile:lvm_add_$LVM_NUM:mount`
		LVM_ADD_VGNAME[$LVM_NUM]=`salt --out newline_values_only $MY_HN pillar.get cloud:profiles:$HN_UNDER:lxc_post_profile:lvm_add_$LVM_NUM:vgname`
		LVM_ADD_LVNAME[$LVM_NUM]=`salt --out newline_values_only $MY_HN pillar.get cloud:profiles:$HN_UNDER:lxc_post_profile:lvm_add_$LVM_NUM:lvname`
		LVM_ADD_SIZE[$LVM_NUM]=`salt --out newline_values_only $MY_HN pillar.get cloud:profiles:$HN_UNDER:lxc_post_profile:lvm_add_$LVM_NUM:size`
	fi
done

# Exit if there is no IP
if [[ -z $HN_IP ]]; then
	echo
	echo "Cloud IP not found, something went wrong. Exiting." | ccze -A
	echo
	exit
fi

# Remove minion key
for O_S_M in $OTHER_SALT_MASTERS; do
	echo
	echo "Removing the minion acceptance (otherwise profile fails) on $O_S_M." | ccze -A
	echo "Going to run: salt $O_S_M cmd.shell 'salt-key -y -d $HN'" | ccze -A
	read -p "Are we OK with that? " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		salt $O_S_M cmd.shell 'salt-key -y -d '$HN
	fi
done

# Remove minion key
echo
echo "Removing the minion acceptance (otherwise profile fails) on $MY_HN." | ccze -A
echo "Going to run: salt $MY_HN cmd.shell 'salt-key -y -d $HN'" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	salt $MY_HN cmd.shell 'salt-key -y -d '$HN
fi

# CloudFlare IP
if [[ "_$CLOUDFLARE_DNS" = "_yes" ]]; then
	echo
	echo "Detected cloud IP in pillars: $HN_IP" | ccze -A
	echo "Going to run: /srv/salt/cloud/cloudflare_add_record.sh $HN $HN_IP" | ccze -A
	read -p "Are we OK with that? " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		/srv/salt/cloud/cloudflare_add_record.sh $HN $HN_IP
	fi
fi

# sysPass password
if [[ "_$SYSPASS" = "_yes" ]]; then
	echo
	echo "Going to run: /srv/salt/cloud/syspass_add_unix_root.sh $HN" | ccze -A
	read -p "Are we OK with that? " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		/srv/salt/cloud/syspass_add_unix_root.sh $HN
	fi
fi

# cloud.profile
echo
echo "Going to run: salt $MY_HN cloud.profile $HN_UNDER $HN" | ccze -A
echo "It could take 10+ minutes." | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	time salt $MY_HN cloud.profile $HN_UNDER $HN
fi

# pkg state
echo
echo "Going to run: salt $HN state.apply cloud.pkg" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	time salt $HN state.apply cloud.pkg
fi

# network state
echo
echo "Going to run: salt $HN state.apply cloud.network" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	time salt $HN state.apply cloud.network
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

# Accept salt0 key
for O_S_M in $OTHER_SALT_MASTERS; do
	echo
	echo "Going to run: salt $O_S_M cmd.shell 'salt-key -y -a $HN'" | ccze -A
	read -p "Are we OK with that? " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		salt $O_S_M cmd.shell 'salt-key -y -a '$HN
	fi
done

# Get some more vars
HOST_SERVER=`salt --out newline_values_only $HN pillar.get location`
POSTGRESQL=`salt --out newline_values_only $HN pillar.get postgres`
APPS=`salt --out newline_values_only $HN pillar.get app:python_apps`

# Exit if there is no HOST_SERVER
if [[ -z $HOST_SERVER ]] || [[ $HOST_SERVER == *"Not connected"* ]] || [[ $HOST_SERVER == *"No response"* ]]; then
	echo
	echo "Host server of the minion container not found, probably container is stopped. Exiting." | ccze -A
	echo
	exit
fi

# Stop container
echo
echo "We need to stop the container for the final steps" | ccze -A
echo "Going to run: salt $HOST_SERVER cmd.shell \"lxc-stop -n $HN\"" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	time salt $HOST_SERVER cmd.shell "lxc-stop -n $HN"
fi

# Add veth pairs
if [[ ! -z $VETH_PAIR_ETH0 ]]; then
	echo
	echo "Adding lxc.network.veth.pair for eth0 to minion config on the host server" | ccze -A
	echo "Going to run: salt $HOST_SERVER cmd.shell " | ccze -A
	echo 'sed -i "s/eth0/eth0\nlxc.network.veth.pair = '$VETH_PAIR_ETH0'" /var/lib/lxc/'$HN'/config' | ccze -A
	read -p "Are we OK with that? " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		salt $HOST_SERVER cmd.shell 'sed -i "s/eth0/eth0\nlxc.network.veth.pair = '$VETH_PAIR_ETH0'" /var/lib/lxc/'$HN'/config'
	fi
fi
if [[ ! -z $VETH_PAIR_ETH1 ]]; then
	echo
	echo "Adding lxc.network.veth.pair for eth0 to minion config on the host server" | ccze -A
	echo "Going to run: salt $HOST_SERVER cmd.shell " | ccze -A
	echo 'sed -i "s/eth1/eth1\nlxc.network.veth.pair = '$VETH_PAIR_ETH1'" /var/lib/lxc/'$HN'/config' | ccze -A
	read -p "Are we OK with that? " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		salt $HOST_SERVER cmd.shell 'sed -i "s/eth0/eth0\nlxc.network.veth.pair = '$VETH_PAIR_ETH1'" /var/lib/lxc/'$HN'/config'
	fi
fi
if [[ ! -z $VETH_PAIR_ETH2 ]]; then
	echo
	echo "Adding lxc.network.veth.pair for eth0 to minion config on the host server" | ccze -A
	echo "Going to run: salt $HOST_SERVER cmd.shell " | ccze -A
	echo 'sed -i "s/eth2/eth2\nlxc.network.veth.pair = '$VETH_PAIR_ETH2'" /var/lib/lxc/'$HN'/config' | ccze -A
	read -p "Are we OK with that? " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		salt $HOST_SERVER cmd.shell 'sed -i "s/eth0/eth0\nlxc.network.veth.pair = '$VETH_PAIR_ETH2'" /var/lib/lxc/'$HN'/config'
	fi
fi

# Resize root
if [[ ! -z $ROOT_RESIZE ]]; then
	echo
	echo "Resizing container root volume on the host server" | ccze -A
	echo "Going to run: salt $HOST_SERVER cmd.shell \"lvresize -r --size $ROOT_RESIZE /dev/$ROOT_VGNAME/$HN\"" | ccze -A
	read -p "Are we OK with that? " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		time salt $HOST_SERVER cmd.shell "lvresize -r --size $ROOT_RESIZE /dev/$ROOT_VGNAME/$HN"
	fi
fi

# Add volumes
for LVM_NUM in 1 2 3 4 5 6 7 8 9; do
	if [[ ! -z ${LVM_ADD_MOUNT[$LVM_NUM]} ]] && [[ ! -z ${LVM_ADD_VGNAME[$LVM_NUM]} ]] && [[ ! -z ${LVM_ADD_LVNAME[$LVM_NUM]} ]] && [[ ! -z ${LVM_ADD_SIZE[$LVM_NUM]} ]]; then
		echo
		echo "Adding volume $LVM_NUM to container on the host server" | ccze -A
		echo "Going to run: salt $HOST_SERVER cmd.shell " | ccze -A
		echo "lvcreate --size ${LVM_ADD_SIZE[$LVM_NUM]} --name ${LVM_ADD_LVNAME[$LVM_NUM]} ${LVM_ADD_VGNAME[$LVM_NUM]}" | ccze -A
		echo "mkfs.ext4 /dev/${LVM_ADD_VGNAME[$LVM_NUM]}/${LVM_ADD_LVNAME[$LVM_NUM]}" | ccze -A
		echo 'echo "lxc.mount.entry = /dev/'${LVM_ADD_VGNAME[$LVM_NUM]}'/'${LVM_ADD_LVNAME[$LVM_NUM]}' '${LVM_ADD_MOUNT[$LVM_NUM]}' ext4 rw,noatime,create=dir 0 2" >> /var/lib/lxc/'$HN'/config' | ccze -A
		read -p "Are we OK with that? " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			salt $HOST_SERVER cmd.shell "lvcreate --size ${LVM_ADD_SIZE[$LVM_NUM]} --name ${LVM_ADD_LVNAME[$LVM_NUM]} ${LVM_ADD_VGNAME[$LVM_NUM]}"
			salt $HOST_SERVER cmd.shell "mkfs.ext4 /dev/${LVM_ADD_VGNAME[$LVM_NUM]}/${LVM_ADD_LVNAME[$LVM_NUM]}"
			salt $HOST_SERVER cmd.shell 'echo "lxc.mount.entry = /dev/'${LVM_ADD_VGNAME[$LVM_NUM]}'/'${LVM_ADD_LVNAME[$LVM_NUM]}' '${LVM_ADD_MOUNT[$LVM_NUM]}' ext4 rw,noatime,create=dir 0 2" >> /var/lib/lxc/'$HN'/config'
		fi
	fi
done

# Start container
echo
echo "Alsmost done, lets start the container" | ccze -A
echo "Going to run: salt $HOST_SERVER cmd.shell \"lxc-start -d -n $HN\"" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	time salt $HOST_SERVER cmd.shell "lxc-start -d -n $HN"
fi

# Remove __base_download
echo
echo "Clean temporary __base_download (do not clean if subsequent identical instances expected on the same host)" | ccze -A
echo "Going to run: salt $HOST_SERVER cmd.shell \"lxc-destroy -n __base_download\"" | ccze -A
read -p "Are we OK with that? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	time salt $HOST_SERVER cmd.shell "lxc-destroy -n __base_download"
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

# Add postgresql backups
if [[ ! -z $POSTGRESQL ]]; then
	echo
	echo "Going to run: salt $HN cmd.shell '/opt/sysadmws-utils/rsnapshot_backup/rsnapshot_backup.conf_postgresql.sh'" | ccze -A
	read -p "Are we OK with that? " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		salt $HN cmd.shell '/opt/sysadmws-utils/rsnapshot_backup/rsnapshot_backup.conf_postgresql.sh'
	fi
fi

# Add ADD_TO_BACKUPS_COMMON_DIRS backups
for B_D in $ADD_TO_BACKUPS_COMMON_DIRS; do
	if [[ ! -z $APPS ]]; then
		echo
		echo "Going to run: salt $HN cmd.shell '/opt/sysadmws-utils/rsnapshot_backup/rsnapshot_backup.conf_path.sh $B_D'" | ccze -A
		read -p "Are we OK with that? " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			salt $HN cmd.shell '/opt/sysadmws-utils/rsnapshot_backup/rsnapshot_backup.conf_path.sh $B_D'
		fi
	fi
done

# Final info
echo
echo "All done. Don't forget to do the following:" | ccze -A
echo "- Add data backups, if needed." | ccze -A
echo "- Add some info to tickets." | ccze -A
