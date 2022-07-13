{% if pillar["rvm"] is defined %}
  {%- set rvm = pillar["rvm"] %}
{% endif %}

{% if rvm is defined %}
rvm_repo:
  pkgrepo.managed:
    - name: deb https://ppa.launchpadcontent.net/rael-gc/rvm/ubuntu {{ grains["oscodename"] }} main 
    - dist: {{ grains["oscodename"] }}
    - file: /etc/apt/sources.list.d/rael-gc-rvm-{{ grains["oscodename"] }}.list
    - keyserver: keyserver.ubuntu.com
    - keyid: F4E3FBBE
    - refresh: True

rvm_pkg:
  pkg.installed:
    - pkgs:
      - rvm

  {%- for ver, ver_enabled in rvm["versions"].items() %}
    {%- if ver_enabled %}
rvm_installed_{{ ver }}:
  cmd.run:
    - name: source /etc/profile.d/rvm.sh && rvm install {{ ver }}
    - shell: /bin/bash

    {%- endif %}
  {%- endfor %}

{% endif %}
