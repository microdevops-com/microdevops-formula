{% if pillar['lxd'] is defined and pillar['lxd'] is not none %}
lxd_depencies_installed:
  pkg.latest:
    - refresh: True
    - pkgs:
      - bridge-utils
      - lvm2
      - gdisk
      - thin-provisioning-tools

lxd_installed:
  pkg.latest:
    - refresh: True
    - fromrepo: {{ grains['oscodename'] }}-backports
    - pkgs:
      - lxd
      - lxd-client

lxd_activate:
  cmd.run:
    - name: 'lxd activateifneeded'

lxd_start:
  service.running:
    - name: lxd
    - enable: True

lxd_init:
  cmd.run:
    - name: 'lxd init --auto --network-address=[::] --network-port=8443 --trust-password={{ pillar['lxd']['password'] }}'

lxd_local_remote:
  cmd.run:
    - name: 'lxc remote list | grep -q -e $(hostname -f) || lxc remote add $(hostname -f) https://localhost:8443 --accept-certificate --password={{ pillar['lxd']['password'] }}'

lxd_remove_lxdbr0:
  cmd.run:
    - name: 'lxc network delete lxdbr0 || true'

lxd_remove_lxdbr0_default_profile:
  cmd.run:
    - name: 'lxc profile device remove default eth0 || true'

lxd_image_xenial:
  cmd.run:
    - name: 'lxc image copy images:ubuntu/xenial/amd64 local: --alias ubuntu/xenial/amd64 --auto-update'

lxd_image_bionic:
  cmd.run:
    - name: 'lxc image copy images:ubuntu/bionic/amd64 local: --alias ubuntu/bionic/amd64 --auto-update'

  {%- if 'images' in pillar['lxd'] %}
    {%- for image_alias, image_source in pillar['lxd']['images'].items() %}
lxd_image_pillar_{{ loop.index }}:
  cmd.run:
    - name: 'lxc image copy {{ image_source }} local: --alias {{ image_alias }} --auto-update'

    {%- endfor %}
  {%- endif %}

lxd_profile_create_autostart:
  cmd.run:
    - name: 'lxc profile list | grep -q -e "| autostart *|" || lxc profile create autostart'

lxd_profile_set_autostart:
  cmd.run:
    - name: 'lxc profile set autostart boot.autostart true'

lxd_profile_create_privileged:
  cmd.run:
    - name: 'lxc profile list | grep -q -e "| privileged *|" || lxc profile create privileged'

lxd_profile_set_privileged:
  cmd.run:
    - name: 'lxc profile set privileged security.privileged true'

lxd_profile_create_nfs:
  cmd.run:
    - name: 'lxc profile list | grep -q -e "| nfs *|" || lxc profile create nfs'

lxd_profile_set_nfs:
  cmd.run:
    - name: 'printf "mount fstype=rpc_pipefs,\nmount fstype=nfsd,\nmount fstype=nfs,\nmount options=(rw, bind, ro)," | lxc profile set nfs raw.apparmor -'

lxd_profile_create_docker:
  cmd.run:
    - name: 'lxc profile list | grep -q -e "| docker *|" || lxc profile create docker'

lxd_profile_set_docker:
  cmd.run:
    - name: 'printf "lxc.apparmor.profile = unconfined\nlxc.cgroup.devices.allow = a\nlxc.mount.auto=proc:rw sys:rw\nlxc.cap.drop =" | lxc profile set docker raw.lxc -; lxc profile set docker security.nesting true; lxc profile set docker security.privileged true; lxc profile set docker linux.kernel_modules "bridge,br_netfilter,ip_tables,ip6_tables,ip_vs,netlink_diag,nf_nat,overlay,xt_conntrack,ip_vs_rr,ip_vs_wrr,ip_vs_sh,nf_conntrack_ipv4"'

  {%- if 'profiles' in pillar['lxd'] %}
    {%- for profile_name, profile_val in pillar['lxd']['profiles'].items() %}
      {%- set a_loop = loop %}
lxd_profile_create_{{ loop.index }}:
  cmd.run:
    - name: 'lxc profile list | grep -q -e "| {{ profile_name }} *|" || lxc profile create {{ profile_name }}'

      {%- if 'devices' in profile_val %}
        {%- for device_name, device_val in profile_val['devices'].items() %}
          {%- set b_loop = loop %}
lxd_profile_device_add_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: 'lxc profile device list {{ profile_name }} | grep -q -e "^{{ device_name }}$" || lxc profile device add {{ profile_name }} {{ device_name }} {{ device_val['type'] }}{% for device_param_key, device_param_val in device_val.items() %} {{ device_param_key }}={{ device_param_val }}{% endfor %}'

          {%- for device_param_key, device_param_val in device_val.items() %}
lxd_profile_device_set_{{ a_loop.index }}_{{ b_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: 'lxc profile device set {{ profile_name }} {{ device_name }} {{ device_param_key }} {{ device_param_val }}'

          {%- endfor %}
        {%- endfor %}
      {%- endif %}

      {%- if 'config' in profile_val %}
        {%- for config_key, config_val in profile_val['config'].items() %}
lxd_profile_config_set_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: 'lxc profile set {{ profile_name }} {{ config_key }} {{ config_val }}'

        {%- endfor %}
      {%- endif %}

    {%- endfor %}
  {%- endif %}
{% endif %}
