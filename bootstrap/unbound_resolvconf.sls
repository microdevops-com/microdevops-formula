bootstrap_unbound_install:
  pkg.latest:
    - pkgs:
      - unbound
      - resolvconf

bootstrap_unbound_stop:
  service.dead:
    - name: unbound

bootstrap_unbound_remove_init:
  file.absent:
    - name: /etc/init.d/unbound

bootstrap_insserv_fix:
  cmd.run:
    - name: 'sed -i "s/unbound/+unbound/" /etc/insserv.conf.d/unbound'

bootstrap_systemd_reload:
  cmd.run:
    - name: 'systemctl daemon-reload'

bootstrap_systemd_init:
  file.managed:
    - name: /lib/systemd/system/unbound.service
    - contents: |
        [Unit]
        Description=Unbound recursive Domain Name Server
        After=network-online.target remote-fs.target systemd-journald-dev-log.socket
        Wants=network-online.target nss-lookup.target
        Before=nss-lookup.target
        
        [Service]
        Type=simple
        Restart=always
        RestartSec=2
        TimeoutStopSec=5
        StartLimitInterval=0
        EnvironmentFile=-/etc/default/unbound
        ExecStartPre=/usr/sbin/unbound-checkconf
        ExecStartPre=-/usr/sbin/unbound-anchor -a /var/lib/unbound/root.key -v
        ExecStart=/usr/sbin/unbound -d $DAEMON_OPTS
        ExecReload=/usr/sbin/unbound-control reload
        LimitNOFILE=infinity
        LimitNPROC=infinity
        
        [Install]
        WantedBy=multi-user.target

bootstrap_unbound_start:
  service.running:
    - name: unbound
    - enable: True

bootstrap_unbound_forward:
  cmd.run:
    - name: 'unbound-control forward'

bootstrap_unbound_resolv_1:
  file.managed:
    - name: /etc/resolvconf/resolv.conf.d/base
    - mode: 0644
    - contents: |
        search {{ pillar['resolv_domain'] }}
        nameserver 127.0.0.1

bootstrap_unbound_resolv_2:
  cmd.run:
    - name: 'ln -nsf /run/resolvconf/resolv.conf /etc/resolv.conf'

bootstrap_unbound_resolv_3:
  cmd.run:
    - name: resolvconf -u

bootstrap_unbound_status_1:
  cmd.run:
    - name: 'systemctl status unbound'

bootstrap_unbound_status_2:
  cmd.run:
    - name: 'unbound-control list_stubs'

bootstrap_unbound_status_3:
  cmd.run:
    - name: 'ping -c 4 yahoo.com'

bootstrap_unbound_status_4:
  cmd.run:
    - name: 'unbound-control stats'
