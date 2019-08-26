{% if pillar['salt'] is defined and pillar['salt'] is not none and pillar['salt']['master'] is defined and pillar['salt']['master'] is not none %}
salt_master_repo:
  pkgrepo.managed:
    - humanname: SaltStack Repository
    - name: deb http://repo.saltstack.com/apt/ubuntu/{{ grains['osrelease'] }}/amd64/{{ pillar['salt']['master']['version'] }} {{ grains['oscodename'] }} main
    - file: /etc/apt/sources.list.d/saltstack.list
    - key_url: https://repo.saltstack.com/apt/ubuntu/{{ grains['osrelease'] }}/amd64/{{ pillar['salt']['master']['version'] }}/SALTSTACK-GPG-KEY.pub
    - clean_file: True

salt_master_pkg:
  pkg.latest:
    - refresh: True
    - pkgs:
        - salt-master
        - salt-ssh

salt_master_config:
  file.serialize:
    - name: /etc/salt/master
    - user: root
    - group: root
    - mode: 644
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: yaml
    - dataset: {{ pillar['salt']['master']['config'] }}

  {%- if pillar['salt']['master']['key'] is defined and pillar['salt']['master']['key'] is not none %}
salt_master_key_1:
  file.managed:
    - name: /etc/salt/pki/master/master.pem
    - user: root
    - group: root
    - mode: 400
    - contents: {{ pillar['salt']['master']['key']['pem'] | yaml_encode }}

salt_master_key_2:
  file.managed:
    - name: /etc/salt/pki/master/master.pub
    - user: root
    - group: root
    - mode: 644
    - contents: {{ pillar['salt']['master']['key']['pub'] | yaml_encode }}
  {%- endif %}

salt_master_service:
  cmd.run:
    - name: service salt-master restart

  {%- if pillar['salt']['master']['repo'] is defined and pillar['salt']['master']['repo'] is not none %}
salt_master_deploy_repo:
  cmd.run:
    - name: |
        [ -d /srv/.git ] || ( cd /srv && git init . && ln -s ../../.githooks/post-merge .git/hooks/post-merge && git remote add origin {{ pillar['salt']['master']['repo'] }} && GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no" git pull origin master && GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no" git submodule init && GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no" git submodule update --recursive -f --checkout && git branch --set-upstream-to=origin/master master && .git/hooks/post-merge )
  {%- endif %}

{% endif %}
