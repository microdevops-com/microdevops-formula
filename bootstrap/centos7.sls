uptodate:
  pkg.uptodate:
    - refresh: True

pkg_epel:
  pkg.latest:
    - refresh: True
    - pkgs:
      - epel-release

remove_firewalld:
  pkg.purged:
    - pkgs:
      - firewalld
      - firewalld-filesystem

install_ufw:
  pkg.latest:
    - refresh: True
    - pkgs:
      - ufw

ufw_fixes_1:
  cmd.run:
    - name: |
        chmod 600 /var/lib/ufw/user.rules /etc/ufw/after6.rules /var/lib/ufw/user6.rules /etc/ufw/before6.rules /etc/ufw/after.rules /etc/ufw/before.rules
        ufw --force disable
        ufw --force reset
        systemctl enable ufw

ufw_fixes_2:
  file.managed:
    - name: /var/lib/ufw/user.rules
    - contents: |
        *filter
        :ufw-user-input - [0:0]
        :ufw-user-output - [0:0]
        :ufw-user-forward - [0:0]
        :ufw-before-logging-input - [0:0]
        :ufw-before-logging-output - [0:0]
        :ufw-before-logging-forward - [0:0]
        :ufw-user-logging-input - [0:0]
        :ufw-user-logging-output - [0:0]
        :ufw-user-logging-forward - [0:0]
        :ufw-after-logging-input - [0:0]
        :ufw-after-logging-output - [0:0]
        :ufw-after-logging-forward - [0:0]
        :ufw-logging-deny - [0:0]
        :ufw-logging-allow - [0:0]
        :ufw-user-limit - [0:0]
        :ufw-user-limit-accept - [0:0]
        ### RULES ###
        
        ### END RULES ###
        
        ### LOGGING ###
        -I ufw-user-logging-input -j RETURN
        -I ufw-user-logging-output -j RETURN
        -I ufw-user-logging-forward -j RETURN
        ### END LOGGING ###
        
        ### RATE LIMITING ###
        -A ufw-user-limit -j REJECT
        -A ufw-user-limit-accept -j ACCEPT
        ### END RATE LIMITING ###
        COMMIT

ufw_fixes_3:
  file.managed:
    - name: /var/lib/ufw/user6.rules
    - contents: |
        *filter
        :ufw6-user-input - [0:0]
        :ufw6-user-output - [0:0]
        :ufw6-user-forward - [0:0]
        :ufw6-before-logging-input - [0:0]
        :ufw6-before-logging-output - [0:0]
        :ufw6-before-logging-forward - [0:0]
        :ufw6-user-logging-input - [0:0]
        :ufw6-user-logging-output - [0:0]
        :ufw6-user-logging-forward - [0:0]
        :ufw6-after-logging-input - [0:0]
        :ufw6-after-logging-output - [0:0]
        :ufw6-after-logging-forward - [0:0]
        :ufw6-logging-deny - [0:0]
        :ufw6-logging-allow - [0:0]
        :ufw6-user-limit - [0:0]
        :ufw6-user-limit-accept - [0:0]
        ### RULES ###
        
        ### END RULES ###
        
        ### LOGGING ###
        -I ufw6-user-logging-input -j RETURN
        -I ufw6-user-logging-output -j RETURN
        -I ufw6-user-logging-forward -j RETURN
        ### END LOGGING ###
        
        ### RATE LIMITING ###
        -A ufw6-user-limit -j REJECT
        -A ufw6-user-limit-accept -j ACCEPT
        ### END RATE LIMITING ###
        COMMIT

pkg_latest:
  pkg.latest:
    - refresh: True
    - pkgs:
      # console tools
      - vim-enhanced
      - nano
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
      # man
      - info
      - man-db
      # tools
      - at
      - rsnapshot
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
      - psmisc
      - telnet
      - strace
      - whois
      - net-tools
      - bmon
      # build
      - gcc
      - gcc-c++
      - kernel-devel
      - make
      - git
      - gawk
      - curl
      - wget
      # security
      - fail2ban
      - iptables
      - openssh-server
      # mail
      - postfix
      # python
      - python3-pip

full_hostname:
  cmd.run:
    - name: |
        echo "{{ pillar["bootstrap"]["hostname"] }}" > /etc/hostname && hostname $(cat /etc/hostname)
