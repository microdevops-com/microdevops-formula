{% if pillar["incus"] is defined %}
incus_keyrings_dir:
  file.directory:
    - name: /etc/apt/keyrings

incus_zabbly_key:
  file.managed:
    - name: /etc/apt/keyrings/zabbly.asc
    - source: https://pkgs.zabbly.com/key.asc
    - skip_verify: True

incus_zabbly_repo:
  file.managed:
    - name: /etc/apt/sources.list.d/zabbly-incus-stable.list
    - contents: |
        deb [arch={{ grains["osarch"] }} signed-by=/etc/apt/keyrings/zabbly.asc] https://pkgs.zabbly.com/incus/stable {{ grains["oscodename"] }} main

incus_installed_with_deps:
  pkg.latest:
    - refresh: True
    - pkgs:
      - bridge-utils
      - lvm2
      - gdisk
      - thin-provisioning-tools
      - incus

incus_lxcfs_systemd_override:
  file.managed:    
    - name: /etc/systemd/system/incus-lxcfs.service.d/override.conf
    - makedirs: True
    - mode: 644
    # ExecStart should be specified twice to override the default value
    - contents: |
        [Service]
        ExecStart=
        ExecStart=/opt/incus/bin/lxcfs --enable-loadavg --enable-cfs --enable-pidfd /var/lib/incus-lxcfs
  module.run:                                                           
    - name: service.systemctl_reload
    - onchanges:
      - file: /etc/systemd/system/incus-lxcfs.service.d/override.conf
    - watch_in:
      - service: incus_lxcfs_service

incus_lxcfs_service: 
  service.running:
    - name: incus-lxcfs
    - enable: True

incus_service: 
  service.running:
    - name: incus
    - enable: True

{% endif %}
