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
  {%- elif grains['oscodename'] == 'stretch' %}
pkg_stretch_sources_list:
  file.managed:
    - name: '/etc/apt/sources.list'
    - source: salt://cloud/files/stretch_sources_list
    - mode: 0644
  {%- elif grains['oscodename'] == 'xenial' %}
pkg_xenial_sources_list:
  file.managed:
    - name: '/etc/apt/sources.list'
    - source: salt://cloud/files/xenial_sources_list
    - mode: 0644
  {%- endif %}

pkg_deb_update:
  pkg.uptodate:
    - refresh: True

pkg_deb_packages:
  pkg.installed:
    - pkgs:
      - tasksel
      - apt-utils
  {%- if grains['oscodename'] == 'jessie' %}
      - python-software-properties
  {%- elif grains['oscodename'] == 'stretch' %}
      - software-properties-common
  {%- elif grains['oscodename'] == 'xenial' %}
      - python-software-properties
  {%- endif %}
      - at
      - doc-debian
      - ftp
  {%- if grains['oscodename'] == 'bionic' %}
      - bind9-host
  {%- else %}
      - host
  {%- endif %}
      - info
      - iputils-ping
      - nano
      - netcat-traditional
      - traceroute
      - util-linux-locales
      - rsyslog
      - less
      - whois
      - bc
      - wamerican
      - ucf
      - dc
      - groff-base
      - man-db
      - bzip2
      - whiptail
  {%- if grains['oscodename'] != 'precise' %}
      - kmod
      - aptitude-common
      - nfacct
  {%- endif %}
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
  {%- if grains['oscodename'] == 'jessie' %}
      - python-reportbug
  {%- elif grains['oscodename'] == 'xenial' %}
      - python-reportbug
  {%- elif grains['oscodename'] == 'stretch' %}
      - python3-reportbug
  {%- endif %}
      - lsof
      - reportbug
      - vim
      - krb5-locales
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
  {%- elif grains['oscodename'] == 'stretch' %}
      - task-english
      - task-ssh-server
      - libxtables12
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
  {%- if grains['oscodename'] == 'bionic' %}
      - s-nail 
  {%- else %}
      - heirloom-mailx
  {%- endif %}
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
      - sysadmws-utils-v1

  {%- if grains['oscodename'] == 'jessie' %}
jessie_bashrc:
  file.managed:
    - name: '/etc/bash.bashrc'
    - source: salt://cloud/files/jessie_bashrc
    - mode: 0644
  {%- elif grains['oscodename'] == 'stretch' %}
stretch_bashrc:
  file.managed:
    - name: '/etc/bash.bashrc'
    - source: salt://cloud/files/stretch_bashrc
    - mode: 0644
  {%- elif grains['oscodename'] == 'xenial' %}
xenial_bashrc:
  file.managed:
    - name: '/etc/bash.bashrc'
    - source: salt://cloud/files/xenial_bashrc
    - mode: 0644
  {%- endif %}
{% elif grains['os'] in ['CentOS', 'RedHat'] %}
pkg_centos_packages:
  pkg.installed:
    - pkgs:
      - at
      - ftp
      - bind-utils
      - info
      - nano
      - traceroute
      - less
      - bc
  {%- if grains['osmajorrelease']|int == 7 %}
      - man-db
  {%- else %}
      - man
  {%- endif %}
      - bzip2
      - patch
      - mutt
      - cpio
      - mlocate
      - telnet
      - iptables
      - lsof
      - vim-enhanced
      - time
      - openssh
      - postfix
      - ca-certificates
      - gawk
      - curl
      - wget
      - iotop
      - screen
      - mc
      - tree
      - git
{% endif %}
