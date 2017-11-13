{% if grains['os'] in ['Ubuntu', 'Debian'] %}
pkg_deb_https_driver:
  pkg.installed:
    - pkgs:
      - apt-transport-https

  {%- if grains['oscodename'] == 'jessie' %}
pkg_jessie_sources_list:
  file.managed:
    - name: '/etc/apt/sources.list'
    - source: salt://cloud/files/jessie_sources_list
    - mode: 0644
  {%- elif grains['oscodename'] == 'xenial' %}
pkg_xenial_sources_list:
  file.managed:
    - name: '/etc/apt/sources.list'
    - source: salt://cloud/files/xenial_sources_list
    - mode: 0644
  {%- endif %}

pkgrepo_deb:
  pkgrepo.managed:
    - file: /etc/apt/sources.list.d/sysadmws.list
    - name: 'deb https://repo.sysadm.ws/sysadmws-apt/ any main'
    - keyid: 2E7DCF8C
    - keyserver: keyserver.ubuntu.com

pkg_deb_update:
  pkg.uptodate:
    - refresh: True

pkg_deb_packages:
  pkg.installed:
    - pkgs:
      - tasksel
      - vim
      - wget
      - apt-utils
      - python-software-properties
      - at
      - doc-debian
      - ftp
      - host
      - info
      - iputils-ping
      - nano
      - netcat-traditional
      - traceroute
      - util-linux-locales
      - rsyslog
      - less
      - whois
      - nfacct
      - bc
      - wamerican
      - ucf
      - dc
      - groff-base
      - man-db
      - bzip2
      - whiptail
      - kmod
      - gettext-base
      - dbus
      - libclass-isa-perl
      - dnsutils
      - libswitch-perl
      - patch
      - mutt
      - manpages
      - cpio
      - mlocate
      - telnet
      - iptables
      - python-reportbug
      - lsof
      - reportbug
      - vim
      - krb5-locales
      - aptitude-common
      - ncurses-term
      - aptitude
      - apt-listchanges
      - bash-completion
      - m4
      - procmail
      - texinfo
      - w3m
      - time
  {%- if grains['oscodename'] == 'jessie' %}
      - task-english
      - task-ssh-server
      - libxtables10
  {%- elif grains['os'] == 'Ubuntu' %}
      - openssh-server
  {%- endif %}
      - postfix
      - resolvconf
      - apt-transport-https
      - ca-certificates
      # some python deps for apps
      - python-boto
      - python-setuptools
      # for automation
      - gawk
      - curl
      - wget
      - heirloom-mailx
      # diag tools
      - ethtool
      - iotop
      - htop
      - nload
      - lsof
      - dnsutils
      - psmisc
      - telnet
      - strace
      # console tools
      - screen
      - tmux
      - byobu
      - mc
      - ncftp
      - man
      - ncdu
      - ccze
      - pv
      - tree
      - bash-completion
      - bc
      - aptitude
      - rsnapshot
      - s3cmd
      # build tools
      - build-essential
      - git
      - checkinstall
      # test tools
      - memtester
      - bonnie++
      - stress
      - smartmontools
      # security tools
      - fail2ban
      #
      - sysadmws-utils

  {%- if grains['oscodename'] == 'jessie' %}
jessie_bashrc:
  file.managed:
    - name: '/etc/bash.bashrc'
    - source: salt://cloud/files/jessie_bashrc
    - mode: 0644
  {%- elif grains['oscodename'] == 'xenial' %}
xenial_bashrc:
  file.managed:
    - name: '/etc/bash.bashrc'
    - source: salt://cloud/files/xenial_bashrc
    - mode: 0644
  {%- endif %}
{%- elif grains['os'] in ['CentOS', 'RedHat'] %}
  'oops'
{%- else %}
  'oops'
{%- endif %}
