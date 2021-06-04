{% if pillar['lxd'] is defined and pillar['lxd'] is not none %}
lxd_depencies_installed:
  pkg.latest:
    - refresh: True
    - pkgs:
      - bridge-utils
      - lvm2
      - gdisk
      - thin-provisioning-tools
      - snapd

lxd_installed:
  cmd.run:
    - name: 'snap install lxd'

lxd_activate:
  cmd.run:
    - name: '/snap/bin/lxd activateifneeded'

lxd_start:
  cmd.run:
    - name: 'systemctl unmask snap.lxd.daemon && systemctl start snap.lxd.daemon'

lxd_wait_0:
  cmd.run:
    - name: 'sleep 5'

lxd_lxcfs_settings:
  cmd.run:
    - name: 'ps ax | grep -v "ps ax" | grep lxcfs | grep enable-loadavg | grep enable-pidfd | grep enable-cfs || ( snap set lxd lxcfs.cfs=true && snap set lxd lxcfs.loadavg=true && snap set lxd lxcfs.pidfd=true && systemctl unmask snap.lxd.daemon && systemctl stop snap.lxd.daemon && systemctl start snap.lxd.daemon )'

lxd_wait_1:
  cmd.run:
    - name: 'sleep 5'

# temporarely create lxdbr0, sometimes it fails to detect needed ip, so create manually with some ip and then remove
lxd_pre_init:
  cmd.run:
    - name: 'lxc network create lxdbr0 ipv4.address=172.16.0.1/12 ipv4.nat=true'

lxd_init:
  cmd.run:
    - name: '/snap/bin/lxd init --auto --network-address=[::] --network-port=8443 --trust-password={{ pillar['lxd']['password'] }}'

lxd_wait_2:
  cmd.run:
    - name: 'sleep 2'

lxd_local_remote:
  cmd.run:
    - name: '/snap/bin/lxc remote list | grep -q -e $(hostname -f) || /snap/bin/lxc remote add $(hostname -f) https://localhost:8443 --accept-certificate --password={{ pillar['lxd']['password'] }}'

lxd_remove_lxdbr0_default_profile:
  cmd.run:
    - name: '/snap/bin/lxc profile device remove default eth0 || true'

lxd_remove_lxdbr0:
  cmd.run:
    - name: '/snap/bin/lxc network delete lxdbr0 || true'

lxd_image_xenial:
  cmd.run:
    - name: '/snap/bin/lxc image copy images:ubuntu/xenial/amd64 local: --alias ubuntu/xenial/amd64 --auto-update'

lxd_image_bionic:
  cmd.run:
    - name: '/snap/bin/lxc image copy images:ubuntu/bionic/amd64 local: --alias ubuntu/bionic/amd64 --auto-update'

lxd_image_focal:
  cmd.run:
    - name: '/snap/bin/lxc image copy images:ubuntu/focal/amd64 local: --alias ubuntu/focal/amd64 --auto-update'

lxd_image_hirsute:
  cmd.run:
    - name: '/snap/bin/lxc image copy images:ubuntu/hirsute/amd64 local: --alias ubuntu/hirsute/amd64 --auto-update'

  {%- if 'images' in pillar['lxd'] %}
    {%- for image_alias, image_source in pillar['lxd']['images'].items() %}
lxd_image_pillar_{{ loop.index }}:
  cmd.run:
    - name: '/snap/bin/lxc image copy {{ image_source }} local: --alias {{ image_alias }} --auto-update'

    {%- endfor %}
  {%- endif %}

lxd_profile_create_autostart:
  cmd.run:
    - name: '/snap/bin/lxc profile list | grep -q -e "| autostart *|" || /snap/bin/lxc profile create autostart'

lxd_profile_set_autostart:
  cmd.run:
    - name: '/snap/bin/lxc profile set autostart boot.autostart true'

lxd_profile_create_privileged:
  cmd.run:
    - name: '/snap/bin/lxc profile list | grep -q -e "| privileged *|" || /snap/bin/lxc profile create privileged'

lxd_profile_set_privileged:
  cmd.run:
    - name: '/snap/bin/lxc profile set privileged security.privileged true'

lxd_profile_create_nfs:
  cmd.run:
    - name: '/snap/bin/lxc profile list | grep -q -e "| nfs *|" || /snap/bin/lxc profile create nfs'

lxd_profile_set_nfs:
  cmd.run:
    - name: 'printf "mount fstype=rpc_pipefs,\nmount fstype=nfsd,\nmount fstype=nfs,\nmount options=(rw, bind, ro)," | /snap/bin/lxc profile set nfs raw.apparmor -'

lxd_profile_create_docker:
  cmd.run:
    - name: '/snap/bin/lxc profile list | grep -q -e "| docker *|" || /snap/bin/lxc profile create docker'

  {%- if grains['oscodename'] in ['focal'] %}
lxd_profile_set_docker:
  cmd.run:
    - name: 'printf "lxc.apparmor.profile = unconfined\nlxc.cgroup.devices.allow = a\nlxc.mount.auto=proc:rw sys:rw\nlxc.cap.drop =" | /snap/bin/lxc profile set docker raw.lxc -; /snap/bin/lxc profile set docker security.nesting true; /snap/bin/lxc profile set docker security.privileged true; /snap/bin/lxc profile set docker linux.kernel_modules "bridge,br_netfilter,ip_tables,ip6_tables,ip_vs,netlink_diag,nf_nat,overlay,xt_conntrack,ip_vs_rr,ip_vs_wrr,ip_vs_sh,nf_conntrack"'

  {%- else %}
lxd_profile_set_docker:
  cmd.run:
    - name: 'printf "lxc.apparmor.profile = unconfined\nlxc.cgroup.devices.allow = a\nlxc.mount.auto=proc:rw sys:rw\nlxc.cap.drop =" | /snap/bin/lxc profile set docker raw.lxc -; /snap/bin/lxc profile set docker security.nesting true; /snap/bin/lxc profile set docker security.privileged true; /snap/bin/lxc profile set docker linux.kernel_modules "bridge,br_netfilter,ip_tables,ip6_tables,ip_vs,netlink_diag,nf_nat,overlay,xt_conntrack,ip_vs_rr,ip_vs_wrr,ip_vs_sh,nf_conntrack_ipv4"'

  {%- endif %}

  {%- if 'profiles' in pillar['lxd'] %}
    {%- for profile_name, profile_val in pillar['lxd']['profiles'].items() %}
      {%- set a_loop = loop %}
lxd_profile_create_{{ loop.index }}:
  cmd.run:
    - name: '/snap/bin/lxc profile list | grep -q -e "| {{ profile_name }} *|" || /snap/bin/lxc profile create {{ profile_name }}'

      {%- if 'devices' in profile_val %}
        {%- for device_name, device_val in profile_val['devices'].items() %}
          {%- set b_loop = loop %}
lxd_profile_device_add_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: '/snap/bin/lxc profile device list {{ profile_name }} | grep -q -e "^{{ device_name }}$" || /snap/bin/lxc profile device add {{ profile_name }} {{ device_name }} {{ device_val['type'] }}{% for device_param_key, device_param_val in device_val.items() %} {{ device_param_key }}={{ device_param_val }}{% endfor %}'

          {%- for device_param_key, device_param_val in device_val.items() %}
lxd_profile_device_set_{{ a_loop.index }}_{{ b_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: '/snap/bin/lxc profile device set {{ profile_name }} {{ device_name }} {{ device_param_key }} {{ device_param_val }}'

          {%- endfor %}
        {%- endfor %}
      {%- endif %}

      {%- if 'config' in profile_val %}
        {%- for config_key, config_val in profile_val['config'].items() %}
lxd_profile_config_set_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: '/snap/bin/lxc profile set {{ profile_name }} {{ config_key }} {{ config_val }}'

        {%- endfor %}
      {%- endif %}

    {%- endfor %}
  {%- endif %}
{% endif %}
