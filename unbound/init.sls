{% if pillar["unbound"] is defined %}
unbound install:
  pkg.installed:
    - name: unbound

unbound remove default configs:
  file.absent:
    - names:
      - /etc/unbound/unbound.conf.d/qname-minimisation.conf
      - /etc/unbound/unbound.conf.d/root-auto-trust-anchor-file.conf

unbound create config:
  file.managed:
    - name: /etc/unbound/unbound.conf.d/main.conf
    - contents: |
        {{ pillar["unbound"]["config"] | indent(8) }}

  {%- if pillar["unbound"]["root_hints"] is defined %}
unbound download root.hints:
  file.managed:
    - name: {{ pillar["unbound"]["root_hints"] }}
    - source: https://www.internic.net/domain/named.cache
    - skip_verify: True
    - makedirs: True
    - user: unbound
    - group: unbound
    - mode: 644
  cron.present:
    - name: "curl -o {{ pillar["unbound"]["root_hints"] }} https://www.internic.net/domain/named.root"
    - identifier: download root.hints for Unbound
    - user: root
    - minute: {{ range(6, 54) | random }}
    - hour: 1
    - daymonth: 1
    - month: '*/2'
  {%- endif %}

  {%- if pillar["unbound"]["logfile"] is defined %}
apparmor setup for write unbound logs to file:
  file.managed:
    - name: /etc/apparmor.d/local/usr.sbin.unbound
    - contents: /var/log/unbound.log rw,

unbound create log file:
  file.managed:
    - name: /var/log/unbound.log
    - user: unbound
    - group: unbound

apparmor reload:
  cmd.run:
    - name: apparmor_parser -r /etc/apparmor.d/usr.sbin.unbound
  {%- endif %}

disable systemd-resolved:
  service.dead:
    - name: systemd-resolved
    - enable: False

remove symlink /etc/resolv.conf:
  file.absent:
    - name: /etc/resolv.conf

create /etc/resolv.conf:
  file.managed:
    - name: /etc/resolv.conf
    - contents: |
        nameserver 127.0.0.1

unbound service running:
  service.running:
    - name: unbound
    - enable: True

unbound service restart:
  cmd.run:
    - name: systemctl restart unbound
    - onchanges:
        - file: /etc/unbound/unbound.conf.d/main.conf
{%- endif %}
