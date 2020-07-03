{% if grains['oscodename'] in ['focal'] %}
salt_repo:
  pkgrepo.managed:
    - humanname: SaltStack Repository
    - name: deb http://repo.saltstack.com/py3/{{ grains['os']|lower }}/{{ grains['osrelease'] }}/amd64/{{ pillar['salt']['minion']['version'] }} {{ grains['oscodename'] }} main
    - file: /etc/apt/sources.list.d/saltstack.list
    - key_url: https://repo.saltstack.com/py3/{{ grains['os']|lower }}/{{ grains['osrelease'] }}/amd64/{{ pillar['salt']['minion']['version'] }}/SALTSTACK-GPG-KEY.pub
    - clean_file: True

salt_minion:
  pkg.latest:
    - refresh: True
    - pkgs:
      - salt-minion

{% endif %}
