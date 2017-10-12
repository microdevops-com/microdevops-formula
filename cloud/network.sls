{% set id_split = grains['id'].split('.') %}
hosts_ipv4_localhost_a:
  host.absent:
    - ip: 127.0.0.1
    - names:
      - localhost

hosts_ipv4_long:
  host.present:
    - ip: 127.0.0.1
    - names:
      - {{ grains['id'] }}

hosts_ipv4_short:
  host.present:
    - ip: 127.0.0.1
    - names:
      - {{ id_split[0] }}

hosts_ipv4_localhost_p:
  host.present:
    - ip: 127.0.0.1
    - names:
      - localhost

hosts_ipv6_localhost_a:
  host.absent:
    - ip: ::1
    - names:
      - localhost
      - ip6-localhost
      - ip6-loopback

hosts_ipv6_long:
  host.present:
    - ip: ::1
    - names:
      - {{ grains['id'] }}

hosts_ipv6_short:
  host.present:
    - ip: ::1
    - names:
      - {{ id_split[0] }}

hosts_ipv6_localhost_p:
  host.present:
    - ip: ::1
    - names:
      - localhost
      - ip6-localhost
      - ip6-loopback

{% if (pillar['salt_masters'] is defined) and (pillar['salt_masters'] is not none) %}
  {%- for s_master in pillar['salt_masters']|sort %}
hosts_salt_{{ loop.index }}:
  host.present:
    - ip: {{ pillar['salt_masters'][s_master] }}
    - names:
      - {{ s_master }}

  {%- endfor %}
{% endif %}

{% if (grains['virtual'] == "LXC") %}
  {%- if (grains['oscodename'] == 'jessie') %}
eth0:
  network.managed:
    - enabled: True
    - type: eth
    - proto: manual
  {%- elif grains['oscodename'] == 'xenial' %}
# state above for some reason doesn't work for xenial, ugly hack below
xenial_network_interfaces:
  file.managed:
    - name: '/etc/network/interfaces'
    - source: salt://cloud/files/xenial_network_interfaces
    - mode: 0644
  {%- endif %}
{% endif %}

resolv_conf_file:
  file.managed:
    - name: /etc/resolvconf/resolv.conf.d/base
    - source: salt://cloud/files/resolv_conf
    - mode: 0644
    - template: jinja
    - defaults:
        resolv_domain: {{ pillar['resolv_domain'] }}

resolv_update:
  cmd.run:
    - name: resolvconf -u
    - onchanges:
      - file: '/etc/resolvconf/resolv.conf.d/base'
