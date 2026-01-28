{% if pillar["incus"] is defined %}
# temporarely create incusbr0, sometimes it fails to detect needed ip, so create manually with some ip and then remove
incus_pre_init:
  cmd.run:
    - name: incus network create incusbr0 ipv4.address=172.16.0.1/12 ipv4.nat=true

incus_init:
  cmd.run:
    - name: incus admin init --auto --network-address=[::] --network-port=8443

incus_waitready:
  cmd.run:
    - name: incus admin waitready

incus_local_named_remote:
  cmd.run:
    - name: incus remote list | grep -q -e $(hostname -f) || incus remote add $(hostname -f) unix://

incus_remove_eth0_default_profile:
  cmd.run:
    - name: incus profile device remove default eth0 || true

incus_remove_incusbr0:
  cmd.run:
    - name: incus network delete incusbr0 || true

  {%- if "images" in pillar["incus"] %}
    {%- for image_alias, image_params in pillar["incus"]["images"].items() %}
incus_image_pillar_{{ loop.index }}:
  cmd.run:
    - name: |
        incus image info {{ image_alias }} {% if "vm" in image_params and image_params["vm"] %}--vm{% endif %} || incus image copy {{ image_params["source"] }} local: --alias {{ image_alias }} --auto-update {% if "vm" in image_params and image_params["vm"] %}--vm{% endif %}

    {%- endfor %}
  {%- endif %}

  {%- if "config" in pillar["incus"] %}
    {%- for config_key, config_val in pillar["incus"]["config"].items() %}
incus_host_config_set_{{ loop.index }}:
  cmd.run:
    - name: incus config set {{ config_key }}={{ config_val }}

    {%- endfor %}
  {%- endif %}

incus_profile_create_autostart:
  cmd.run:
    - name: incus profile list | grep -q -e "| autostart *|" || incus profile create autostart

incus_profile_set_autostart:
  cmd.run:
    - name: incus profile set autostart boot.autostart true

incus_profile_create_privileged:
  cmd.run:
    - name: incus profile list | grep -q -e "| privileged *|" || incus profile create privileged

incus_profile_set_privileged:
  cmd.run:
    - name: incus profile set privileged security.privileged true

incus_profile_create_nfs:
  cmd.run:
    - name: incus profile list | grep -q -e "| nfs *|" || incus profile create nfs

incus_profile_set_nfs:
  cmd.run:
    - name: printf "mount fstype=rpc_pipefs,\nmount fstype=nfsd,\nmount fstype=nfs,\nmount options=(rw, bind, ro)," | incus profile set nfs raw.apparmor -

incus_profile_create_docker:
  cmd.run:
    - name: incus profile list | grep -q -e "| docker *|" || incus profile create docker

incus_profile_set_docker:
  cmd.run:
    - name: printf "lxc.apparmor.profile = unconfined\nlxc.cgroup.devices.allow = a\nlxc.mount.auto=proc:rw sys:rw\nlxc.cap.drop =" | incus profile set docker raw.lxc -; incus profile set docker security.nesting true; incus profile set docker security.privileged true; incus profile set docker linux.kernel_modules "bridge,br_netfilter,ip_tables,ip6_tables,ip_vs,netlink_diag,nf_nat,overlay,xt_conntrack,ip_vs_rr,ip_vs_wrr,ip_vs_sh,nf_conntrack"

  {%- if "profiles" in pillar["incus"] %}
    {%- for profile_name, profile_val in pillar["incus"]["profiles"].items() %}
      {%- set a_loop = loop %}
incus_profile_create_{{ loop.index }}:
  cmd.run:
    - name: incus profile list | grep -q -e "| {{ profile_name }} *|" || incus profile create {{ profile_name }}

      {%- if "devices" in profile_val %}
        {%- for device_name, device_val in profile_val["devices"].items() %}
          {%- set b_loop = loop %}
incus_profile_device_add_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: incus profile device list {{ profile_name }} | grep -q -e "^{{ device_name }}$" || incus profile device add {{ profile_name }} {{ device_name }} {{ device_val["type"] }}{% for device_param_key, device_param_val in device_val.items() %} {{ device_param_key }}={{ device_param_val }}{% endfor %}

          {%- for device_param_key, device_param_val in device_val.items() %}
incus_profile_device_set_{{ a_loop.index }}_{{ b_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: incus profile device set {{ profile_name }} {{ device_name }} {{ device_param_key }} {{ device_param_val }}

          {%- endfor %}
        {%- endfor %}
      {%- endif %}

      {%- if "config" in profile_val %}
        {%- for config_key, config_val in profile_val["config"].items() %}
incus_profile_config_set_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: incus profile set {{ profile_name }} {{ config_key }} {{ config_val }}

        {%- endfor %}
      {%- endif %}

    {%- endfor %}
  {%- endif %}

{% endif %}
