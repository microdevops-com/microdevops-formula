{% if pillar["lxd"] is defined %}
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
    - prepend_path: /snap/bin
    - name: snap install lxd

lxd_activate:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxd activateifneeded

lxd_start:
  cmd.run:
    - prepend_path: /snap/bin
    - name: systemctl unmask snap.lxd.daemon && systemctl start snap.lxd.daemon

lxd_wait_0:
  cmd.run:
    - prepend_path: /snap/bin
    - name: sleep 5

lxd_lxcfs_settings:
  cmd.run:
    - prepend_path: /snap/bin
    - name: ps ax | grep -v "ps ax" | grep lxcfs | grep enable-loadavg | grep enable-pidfd | grep enable-cfs || ( snap set lxd lxcfs.cfs=true && snap set lxd lxcfs.loadavg=true && snap set lxd lxcfs.pidfd=true && systemctl unmask snap.lxd.daemon && systemctl stop snap.lxd.daemon && systemctl start snap.lxd.daemon )

lxd_wait_1:
  cmd.run:
    - prepend_path: /snap/bin
    - name: sleep 5

# temporarely create lxdbr0, sometimes it fails to detect needed ip, so create manually with some ip and then remove
lxd_pre_init:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc network create lxdbr0 ipv4.address=172.16.0.1/12 ipv4.nat=true

lxd_init:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxd init --auto --network-address=[::] --network-port=8443 --trust-password={{ pillar["lxd"]["password"] }}

lxd_wait_2:
  cmd.run:
    - prepend_path: /snap/bin
    - name: sleep 2

lxd_local_remote:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc remote list | grep -q -e $(hostname -f) || lxc remote add $(hostname -f) https://localhost:8443 --accept-certificate --password={{ pillar["lxd"]["password"] }}

lxd_remove_lxdbr0_default_profile:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc profile device remove default eth0 || true

lxd_remove_lxdbr0:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc network delete lxdbr0 || true

  {%- if "images" in pillar["lxd"] %}
    {%- for image_alias, image_params in pillar["lxd"]["images"].items() %}
lxd_image_pillar_{{ loop.index }}:
  cmd.run:
    - prepend_path: /snap/bin
    - name: |
        lxc image copy {{ image_params["source"] }} local: --alias {{ image_alias }} --auto-update {% if "vm" in image_params and image_params["vm"] %}--vm{% endif %}

    {%- endfor %}
  {%- endif %}

lxd_profile_create_autostart:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc profile list | grep -q -e "| autostart *|" || lxc profile create autostart

lxd_profile_set_autostart:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc profile set autostart boot.autostart true

lxd_profile_create_privileged:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc profile list | grep -q -e "| privileged *|" || lxc profile create privileged

lxd_profile_set_privileged:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc profile set privileged security.privileged true

lxd_profile_create_nfs:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc profile list | grep -q -e "| nfs *|" || lxc profile create nfs

lxd_profile_set_nfs:
  cmd.run:
    - prepend_path: /snap/bin
    - name: printf "mount fstype=rpc_pipefs,\nmount fstype=nfsd,\nmount fstype=nfs,\nmount options=(rw, bind, ro)," | lxc profile set nfs raw.apparmor -

lxd_profile_create_docker:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc profile list | grep -q -e "| docker *|" || lxc profile create docker

  {%- if grains["oscodename"] in ["focal", "jammy"] %}
lxd_profile_set_docker:
  cmd.run:
    - prepend_path: /snap/bin
    - name: printf "lxc.apparmor.profile = unconfined\nlxc.cgroup.devices.allow = a\nlxc.mount.auto=proc:rw sys:rw\nlxc.cap.drop =" | lxc profile set docker raw.lxc -; lxc profile set docker security.nesting true; lxc profile set docker security.privileged true; lxc profile set docker linux.kernel_modules "bridge,br_netfilter,ip_tables,ip6_tables,ip_vs,netlink_diag,nf_nat,overlay,xt_conntrack,ip_vs_rr,ip_vs_wrr,ip_vs_sh,nf_conntrack"

  {%- else %}
lxd_profile_set_docker:
  cmd.run:
    - prepend_path: /snap/bin
    - name: printf "lxc.apparmor.profile = unconfined\nlxc.cgroup.devices.allow = a\nlxc.mount.auto=proc:rw sys:rw\nlxc.cap.drop =" | lxc profile set docker raw.lxc -; lxc profile set docker security.nesting true; lxc profile set docker security.privileged true; lxc profile set docker linux.kernel_modules "bridge,br_netfilter,ip_tables,ip6_tables,ip_vs,netlink_diag,nf_nat,overlay,xt_conntrack,ip_vs_rr,ip_vs_wrr,ip_vs_sh,nf_conntrack_ipv4"

  {%- endif %}

  {%- if "profiles" in pillar["lxd"] %}
    {%- for profile_name, profile_val in pillar["lxd"]["profiles"].items() %}
      {%- set a_loop = loop %}
lxd_profile_create_{{ loop.index }}:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc profile list | grep -q -e "| {{ profile_name }} *|" || lxc profile create {{ profile_name }}

      {%- if "devices" in profile_val %}
        {%- for device_name, device_val in profile_val["devices"].items() %}
          {%- set b_loop = loop %}
lxd_profile_device_add_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc profile device list {{ profile_name }} | grep -q -e "^{{ device_name }}$" || lxc profile device add {{ profile_name }} {{ device_name }} {{ device_val["type"] }}{% for device_param_key, device_param_val in device_val.items() %} {{ device_param_key }}={{ device_param_val }}{% endfor %}

          {%- for device_param_key, device_param_val in device_val.items() %}
lxd_profile_device_set_{{ a_loop.index }}_{{ b_loop.index }}_{{ loop.index }}:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc profile device set {{ profile_name }} {{ device_name }} {{ device_param_key }} {{ device_param_val }}

          {%- endfor %}
        {%- endfor %}
      {%- endif %}

      {%- if "config" in profile_val %}
        {%- for config_key, config_val in profile_val["config"].items() %}
lxd_profile_config_set_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc profile set {{ profile_name }} {{ config_key }} {{ config_val }}

        {%- endfor %}
      {%- endif %}

    {%- endfor %}
  {%- endif %}

# As we are migrating to incus, disable lxd snap auto update
lxd_snap_hold:
  cmd.run:
    - prepend_path: /snap/bin
    - name: snap refresh --hold=forever lxd

{% endif %}
