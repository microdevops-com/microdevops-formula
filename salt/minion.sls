{% if pillar['salt'] is defined and 'minion' in pillar['salt'] %}

  {%- for host in pillar['salt']['minion']['hosts'] %}
salt_master_hosts_{{ loop.index }}:
  host.present:
    - ip: {{ host['ip'] }}
    - names:
        - {{ host['name'] }}
  {%- endfor %}

  {%- if grains['os'] in ['Windows'] %}
    {%- if pillar['salt']['minion']['version']|string == '3001' %}
      {%- set minion_exe = 'Salt-Minion-3001.4-Py3-AMD64-Setup.exe' -%}
    {%- endif %}

    {%- if 
           pillar['salt']['minion']['version']|string != grains['saltversioninfo'][0]|string
           or
           (pillar['salt']['minion']['release'] is defined and pillar['salt']['minion']['release'] != grains['saltversioninfo'][0]|string + '.' + grains['saltversioninfo'][1]|string)
    %}
minion_installer_exe:
  file.managed:
    - name: 'C:\Windows\{{ minion_exe }}'
    - source: salt://salt/{{ minion_exe }}

minion_install_silent_cmd:
  cmd.run:
    - name: 'START /B C:\Windows\{{ minion_exe }} /S /master={{ pillar['salt']['minion']['config']['master']|join(',') }} /minion-name={{ grains['fqdn'] }} /start-minion=1'
    {%- endif %}

    {%- if pillar['salt']['minion']['grains_file_rm'] is defined and pillar['salt']['minion']['grains_file_rm'] %}
salt_minion_grains_file_rm:
  file.absent:
    - name: 'C:\salt\conf\grains'
    {%- endif %}

salt_minion_id:
  file.managed:
    - name: 'C:\salt\conf\minion_id'
    - contents: |
        {{ grains['fqdn'] }}

salt_minion_config:
  file.serialize:
    - name: 'C:\salt\conf\minion'
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: yaml
    - dataset: {{ pillar['salt']['minion']['config'] }}

salt_minion_config_restart:
  module.run:
    - name: service.restart
    - m_name: salt-minion
    - onchanges:
        - file: 'C:\salt\conf\minion'
        - file: 'C:\salt\conf\grains'
        - file: 'C:\salt\conf\minion_id'

  {%- elif grains['os'] in ['Ubuntu', 'Debian', 'CentOS'] %}
    {%- if grains['os'] in ['Ubuntu', 'Debian'] and grains['oscodename'] in ['xenial', 'bionic', 'focal'] %}

salt_minion_repo:
  pkgrepo.managed:
    - humanname: SaltStack Repository
    - name: deb https://repo.saltstack.com/py3/{{ grains['os']|lower }}/{{ grains['osrelease'] }}/amd64/{{ pillar['salt']['minion']['version'] }} {{ grains['oscodename'] }} main
    - file: /etc/apt/sources.list.d/saltstack.list
    - key_url: https://repo.saltstack.com/py3/{{ grains['os']|lower }}/{{ grains['osrelease'] }}/amd64/{{ pillar['salt']['minion']['version'] }}/SALTSTACK-GPG-KEY.pub
    - clean_file: True
    - refresh: True

      {%- if pillar['salt']['minion']['version']|string != grains['saltversioninfo'][0]|string %}
salt_minion_update_restart:
  cmd.run:
    - name: |
        exec 0>&- # close stdin
        exec 1>&- # close stdout
        exec 2>&- # close stderr
        nohup /bin/sh -c 'apt-get update; apt-get -qy -o 'DPkg::Options::=--force-confold' -o 'DPkg::Options::=--force-confdef' install --allow-downgrades salt-common={{ pillar['salt']['minion']['version']|string }}* salt-minion={{ pillar['salt']['minion']['version']|string }}* && salt-call --local service.restart salt-minion' &
      {%- endif %}

    {%- endif %}

    {%- if pillar['salt']['minion']['grains_file_rm'] is defined and pillar['salt']['minion']['grains_file_rm'] %}
salt_minion_grains_file_rm:
  file.absent:
    - name: /etc/salt/grains
    {%- endif %}

salt_minion_id:
  file.managed:
    - name: /etc/salt/minion_id
    - contents: |
        {{ grains['fqdn'] }}

salt_minion_config:
  file.serialize:
    - name: /etc/salt/minion
    - user: root
    - group: root
    - mode: 644
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: yaml
    - dataset: {{ pillar['salt']['minion']['config'] }}

salt_minion_config_restart:
  cmd.run:
    - name: |
        exec 0>&- # close stdin
        exec 1>&- # close stdout
        exec 2>&- # close stderr
        nohup /bin/sh -c 'salt-call --local service.restart salt-minion' &
    - onchanges:
        - file: /etc/salt/minion
        - file: /etc/salt/grains
        - file: /etc/salt/minion_id

  {%- endif %}

{% endif %}
