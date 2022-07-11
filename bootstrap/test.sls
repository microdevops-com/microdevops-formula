resolvers_test:
  cmd.run:
    - name: |
{% if grains["oscodename"] in ["bionic", "focal", "jammy"] %}
        grep "nameserver 8.8.8.8" /run/systemd/resolve/resolv.conf && \
        grep "nameserver 8.8.4.4" /run/systemd/resolve/resolv.conf && \
        grep "nameserver 1.1.1.1" /run/systemd/resolve/resolv.conf
{% elif grains["oscodename"] == "bullseye" %}
        grep "nameserver 1.1.1.1" /etc/resolv.conf
{% elif grains["osfinger"] == "CentOS Linux-7" %}
        grep "nameserver 8.8.8.8" /etc/resolv.conf && \
        grep "nameserver 8.8.4.4" /etc/resolv.conf && \
        grep "nameserver 1.1.1.1" /etc/resolv.conf
{% endif %}

full_hostname:
  cmd.run:
    - name: |
        grep {{ grains["id"] }} /etc/hostname && \
        grep {{ grains["id"] }} /etc/hosts && \
        hostname | grep {{ grains["id"] }} && \
        hostname -f | grep {{ grains["id"] }} && \
  {%- if "domain" in pillar["bootstrap"] %}
        grep "search {{ pillar["bootstrap"]["domain"] }}" /etc/resolv.conf
  {%- elif "network" in pillar["bootstrap"] and "domain" in pillar["bootstrap"]["network"] %}
        grep "search {{ pillar["bootstrap"]["network"]["domain"] }}" /etc/resolv.conf
  {%- else %}
        grep "search local" /etc/resolv.conf
  {%- endif %}

memory_accounting:
  cmd.run:
    - name: |
        grep cgroup_enable=memory /proc/cmdline && \
        grep swapaccount=1 /proc/cmdline

{% if grains["virtual"] == "physical" %}
smartd_test:
  cmd.run:
    - name: systemctl is-active smartd

smartctl_test:
  cmd.run:
    - name: |
        for d in $(lsblk -l | grep disk | awk '{print $1}'); do smartctl -a /dev/${d}; done

time_sync_test:
  cmd.run:
    - name: systemctl is-active systemd-timesyncd

mdadm_test:
  cmd.run:
    - name: |
        mdadm --monitor -1 /dev/md0 --test 2>&1 | grep "Monitor using email"

br_netfilter_test:
  cmd.run:
    - name: |
        lsmod | grep br_netfilter || grep br_netfilter /lib/modules/$(uname -r)/modules.builtin && \
  {% if 'firewall_bridge_filter' in pillar["bootstrap"] and pillar["bootstrap"]['firewall_bridge_filter'] %}
        grep 1 /proc/sys/net/bridge/bridge-nf-call-arptables && \
        grep 1 /proc/sys/net/bridge/bridge-nf-call-ip6tables && \
        grep 1 /proc/sys/net/bridge/bridge-nf-call-iptables && \
        grep 1 /proc/sys/net/bridge/bridge-nf-filter-pppoe-tagged && \
        grep 1 /proc/sys/net/bridge/bridge-nf-filter-vlan-tagged && \
        grep 1 /proc/sys/net/bridge/bridge-nf-pass-vlan-input-dev
  {% else %}
        grep 0 /proc/sys/net/bridge/bridge-nf-call-arptables && \
        grep 0 /proc/sys/net/bridge/bridge-nf-call-ip6tables && \
        grep 0 /proc/sys/net/bridge/bridge-nf-call-iptables && \
        grep 0 /proc/sys/net/bridge/bridge-nf-filter-pppoe-tagged && \
        grep 0 /proc/sys/net/bridge/bridge-nf-filter-vlan-tagged && \
        grep 0 /proc/sys/net/bridge/bridge-nf-pass-vlan-input-dev
  {% endif %}
{% endif %}
