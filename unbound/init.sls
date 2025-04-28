{% if pillar["unbound"] is defined %}
unbound_install:
  pkg.installed:
    - name: unbound

unbound_remove_default_configs:
  file.absent:
    - names:
      - /etc/unbound/unbound.conf.d/qname-minimisation.conf
      - /etc/unbound/unbound.conf.d/root-auto-trust-anchor-file.conf
      - /etc/unbound/unbound.conf.d/remote-control.conf

unbound_control_setup:
  cmd.run:
    - name: unbound-control-setup
    - unless: test -f /etc/unbound/unbound_control.pem

  {%- set files = pillar["unbound"].get("files", {}) %}
  {%- if files is none %}
    {%- set files = {} %}
  {%- endif %}
  {%- set file_manager_defaults = {"default_user": "root", "default_group": "root"} %}
  {%- include "_include/file_manager/init.sls" with context %}

  {%- if pillar["unbound"]["root_hints"] is defined %}
unbound_download_root_hints:
  file.managed:
    - name: {{ pillar["unbound"]["root_hints"] }}
    - source: https://www.internic.net/domain/named.cache
    - skip_verify: True
    - makedirs: True
    - user: unbound
    - group: unbound
    - mode: 644

unbound_root_hints_cron:
  cron.present:
    - name: "curl -o {{ pillar["unbound"]["root_hints"] }} https://www.internic.net/domain/named.root"
    - identifier: download root.hints for Unbound
    - user: root
    - minute: 15
    - hour: 1
    - daymonth: 1
    - month: "*/2"

  {%- endif %}

unbound_create_log_file:
  file.managed:
    - name: {{ pillar["unbound"]["logfile"] }}
    - user: unbound
    - group: unbound

unbound_disable_systemd-resolved:
  service.dead:
    - name: systemd-resolved
    - enable: False

unbound_service_running:
  service.running:
    - name: unbound
    - enable: True

unbound_checkconf:
  cmd.run:
    - name: unbound-checkconf

unbound_service_restart:
  cmd.run:
    - name: systemctl restart unbound
    - onchanges:
        - file: /etc/unbound/*
    - require:
        - cmd: unbound_checkconf

unbound_remove_symlink_etc_resolv_conf:
  file.absent:
    - name: /etc/resolv.conf
    - onlyif: test -L /etc/resolv.conf

unbound_create_etc_resolv_conf:
  file.managed:
    - name: /etc/resolv.conf
    - contents: |
        nameserver 127.0.0.1

{%- endif %}
