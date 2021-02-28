{% if pillar["salt"] is defined and "master" in pillar["salt"] %}
salt_master_dirs_1:
  file.directory:
    - names: 
      - /etc/salt
      - /etc/salt/pki
    - user: root
    - group: root
    - mode: 755

salt_master_dirs_2:
  file.directory:
    - names: 
      - /root/.ssh
      - /etc/salt/pki/master
    - user: root
    - group: root
    - mode: 700

salt_master_dirs_3:
  file.directory:
    - names: 
      - /etc/salt/pki/master/minions
      - /etc/salt/pki/master/minions_autosign
      - /etc/salt/pki/master/minions_denied
      - /etc/salt/pki/master/minions_pre
      - /etc/salt/pki/master/minions_rejected
    - user: root
    - group: root
    - mode: 755

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
    - dataset: {{ pillar["salt"]["master"]["config"] }}

  {%- if "pki" in pillar["salt"]["master"] and "master" in pillar["salt"]["master"]["pki"] %}
salt_master_pki_master_pem:
  file.managed:
    - name: /etc/salt/pki/master/master.pem
    - user: root
    - group: root
    - mode: 400
    - contents: {{ pillar["salt"]["master"]["pki"]["master"]["pem"] | yaml_encode }}

salt_master_pki_master_pub:
  file.managed:
    - name: /etc/salt/pki/master/master.pub
    - user: root
    - group: root
    - mode: 644
    - contents: {{ pillar["salt"]["master"]["pki"]["master"]["pub"] | yaml_encode }}

salt_master_pki_master_sign_pem:
  file.managed:
    - name: /etc/salt/pki/master/master_sign.pem
    - user: root
    - group: root
    - mode: 400
    - contents: {{ pillar["salt"]["master"]["pki"]["master_sign"]["pem"] | yaml_encode }}

salt_master_pki_master_sign_pub:
  file.managed:
    - name: /etc/salt/pki/master/master_sign.pub
    - user: root
    - group: root
    - mode: 644
    - contents: {{ pillar["salt"]["master"]["pki"]["master_sign"]["pub"] | yaml_encode }}

    {%- for minion_name, minion_pub in pillar["salt"]["master"]["pki"]["minions"].items() %}
salt_master_pki_minion_pub_{{ loop.index }}:
  file.managed:
    - name: /etc/salt/pki/master/minions/{{ minion_name }}
    - user: root
    - group: root
    - mode: 644
    - contents: {{ minion_pub | yaml_encode }}

    {%- endfor %}

  {%- endif %}

  {%- if "root_ed25519" in pillar["salt"]["master"] %}
salt_master_root_ed25519_priv:
  file.managed:
    - name: /root/.ssh/id_ed25519
    - user: root
    - group: root
    - mode: 400
    - contents: {{ pillar["salt"]["master"]["root_ed25519"]["priv"] | yaml_encode }}

salt_master_root_ed25519_pub:
  file.managed:
    - name: /root/.ssh/id_ed25519.pub
    - user: root
    - group: root
    - mode: 644
    - contents: {{ pillar["salt"]["master"]["root_ed25519"]["pub"] | yaml_encode }}

  {%- endif %}

  {%- if "root_rsa" in pillar["salt"]["master"] %}
salt_master_root_rsa_priv:
  file.managed:
    - name: /root/.ssh/id_rsa
    - user: root
    - group: root
    - mode: 400
    - contents: {{ pillar["salt"]["master"]["root_rsa"]["priv"] | yaml_encode }}

salt_master_root_rsa_pub:
  file.managed:
    - name: /root/.ssh/id_rsa.pub
    - user: root
    - group: root
    - mode: 644
    - contents: {{ pillar["salt"]["master"]["root_rsa"]["pub"] | yaml_encode }}

  {%- endif %}

  {%- if grains["os"] in ["Ubuntu"] and grains["oscodename"] in ["xenial", "bionic", "focal"] %}
salt_master_repo:
  pkgrepo.managed:
    - humanname: SaltStack Repository
    - name: deb https://repo.saltstack.com/py3/{{ grains["os"]|lower }}/{{ grains["osrelease"] }}/{{ grains["osarch"] }}/{{ pillar["salt"]["master"]["version"] }} {{ grains["oscodename"] }} main
    - file: /etc/apt/sources.list.d/saltstack.list
    - key_url: https://repo.saltstack.com/py3/{{ grains["os"]|lower }}/{{ grains["osrelease"] }}/{{ grains["osarch"] }}/{{ pillar["salt"]["master"]["version"] }}/SALTSTACK-GPG-KEY.pub
    - clean_file: True

  {%- endif %}

salt_master_pkg:
  pkg.latest:
    - refresh: True
    - pkgs:
        - salt-master
        - salt-ssh

salt_master_service:
  cmd.run:
    - name: service salt-master restart

  {%- if pillar["salt"]["master"]["repo"] is defined and pillar["salt"]["master"]["repo"] is not none %}
salt_master_deploy_repo:
  cmd.run:
    - name: |
        [ -d /srv/.git ] || ( cd /srv && git init . && ln -s ../../.githooks/post-merge .git/hooks/post-merge && git remote add origin {{ pillar["salt"]["master"]["repo"] }} && GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no" git pull origin master && GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no" git submodule init && GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no" git submodule update --recursive -f --checkout && git branch --set-upstream-to=origin/master master && .git/hooks/post-merge )

salt_master_update_repo:
  cmd.run:
    - name: |
        [ -d /srv/.git ] && ( cd /srv && GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no" git pull && GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no" git fetch --prune origin +refs/tags/*:refs/tags/* && GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no" git submodule init && GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no" git submodule update -f --checkout && GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no" git submodule foreach "git checkout master && git pull && git fetch --prune origin +refs/tags/*:refs/tags/*" )
  {%- endif %}

{% endif %}
