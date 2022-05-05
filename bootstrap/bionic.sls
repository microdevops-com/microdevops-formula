uptodate:
  pkg.uptodate:
    - refresh: True

dist_upgrade:
  cmd.run:
    - name: |
        apt-get -qy -o "DPkg::Options::=--force-confold" -o "DPkg::Options::=--force-confdef" dist-upgrade

bashrc:
  file.managed:
    - name: /etc/bash.bashrc
    - source: salt://bootstrap/files/bashrc/{{ grains["oscodename"] }}
    - mode: 0644

pkg_latest:
  pkg.latest:
    - refresh: True
    - pkgs:
      # console tools
      - vim
      - nano
      - links
      - screen
      - tmux
      - byobu
      - mc
      - ftp
      - ncftp
      - ncdu
      - ccze
      - pv
      - tree
      - bash-completion
      - bc
      - locales
      # apt
      - apt-transport-https
      - apt-listchanges
      - gnupg
      - python3-apt
      # man
      - doc-debian
      - info
      - man-db
      - manpages
      # tools
      - at
      - rsnapshot
      - util-linux-locales
      - mlocate
      # libs
      - ncurses-term
      # diag
      - traceroute
      - ethtool
      - iotop
      - htop
      - nload
      - lsof
      - dnsutils
      - psmisc
      - telnet
      - strace
      - whois
      - net-tools
      - iputils-ping
      - bmon
      # build
      - build-essential
      - git
      - checkinstall
      - gawk
      - curl
      - wget
      # security
      - fail2ban
      - iptables
      - openssh-server
      # mail
      - postfix
      - s-nail 
      # python
      - python3-pip
{% if grains["virtual"] == "physical" %}
      # physical
      - smartmontools
      - bridge-utils
      # stress
      - memtester
      - bonnie++
      - stress
{% endif %}

full_hostname:
  cmd.run:
    - name: |
        echo "{{ pillar["bootstrap"]["hostname"] }}" > /etc/hostname && hostname $(cat /etc/hostname)

{% if grains["virtual"] == "physical" %}
swapiness:
  sysctl.present:
    - name: vm.swappiness
    - value: 10

debconf_utils:
  pkg.latest:
    - reload_modules: True
    - pkgs:
      - debconf-utils

mdadm_config_hack:
  file.replace:
    - name: /etc/mdadm/mdadm.conf
    - pattern: '^MAILADDR .*$'
    - repl: 'MAILADDR {{ pillar["bootstrap"]["monitoring"]["email"] }}'

mdadm_debconf:
  debconf.set:
    - name: mdadm
    - data:
        'mdadm/mail_to': {'type': 'string', 'value': '{{ pillar["bootstrap"]["monitoring"]["email"] }}' }
        'mdadm/start_daemon': {'type': 'boolean', 'value': True}
        'mdadm/autocheck': {'type': 'boolean', 'value': True}
        'mdadm/autoscan': {'type': 'boolean', 'value': True}

mdadm_reconfigure:
  cmd.run:
    - name: dpkg-reconfigure -f noninteractive mdadm
    - onchanges:
      - debconf: mdadm_debconf

br_netfilter_module:
  file.line:
    - name: /etc/modules-load.d/modules.conf
    - content: br_netfilter
    - mode: ensure
    - after: '^#$'

br_netfilter_modprobe:
  cmd.run:
    - name: modprobe br_netfilter

  {% if 'firewall_bridge_filter' in pillar["bootstrap"] and pillar["bootstrap"]['firewall_bridge_filter'] %}
net.bridge.bridge-nf-call-arptables:
  sysctl.present:
    - value: 1

net.bridge.bridge-nf-call-ip6tables:
  sysctl.present:
    - value: 1

net.bridge.bridge-nf-call-iptables:
  sysctl.present:
    - value: 1

net.bridge.bridge-nf-filter-pppoe-tagged:
  sysctl.present:
    - value: 1

net.bridge.bridge-nf-filter-vlan-tagged:
  sysctl.present:
    - value: 1

net.bridge.bridge-nf-pass-vlan-input-dev:
  sysctl.present:
    - value: 1
  {% else %}
net.bridge.bridge-nf-call-arptables:
    sysctl.present:
          - value: 0

net.bridge.bridge-nf-call-ip6tables:
    sysctl.present:
          - value: 0

net.bridge.bridge-nf-call-iptables:
    sysctl.present:
          - value: 0

net.bridge.bridge-nf-filter-pppoe-tagged:
    sysctl.present:
          - value: 0

net.bridge.bridge-nf-filter-vlan-tagged:
    sysctl.present:
          - value: 0

net.bridge.bridge-nf-pass-vlan-input-dev:
    sysctl.present:
          - value: 0
  {% endif %}
{% endif %}
