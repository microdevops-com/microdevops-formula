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

salt_master_rm_old_repo_key:
  file.absent:
    - name: /etc/apt/keyrings/salt-archive-keyring-2023.gpg

salt_master_repo_key:
  file.managed:
    - name: /etc/apt/keyrings/salt-archive-keyring-2023.pgp
    - source: https://packages.broadcom.com/artifactory/api/security/keypair/SaltProjectKey/public
    - skip_verify: True

salt_master_repo_list:
  file.managed:
    - name: /etc/apt/sources.list.d/saltstack.list # Salt version is not in the repo URL, so we need to check it in the package
    - contents: |
        deb [signed-by=/etc/apt/keyrings/salt-archive-keyring-2023.pgp arch=amd64] https://packages.broadcom.com/artifactory/saltproject-deb/ stable main

salt_minion_apt_pin:
  file.managed:
    - name: /etc/apt/preferences.d/salt-pin-1001
    - contents: |
        Package: salt-*
        Pin: version {{ pillar["salt"]["master"]["version"] }}.*
        Pin-Priority: 1001

salt_master_pkg:
  pkg.latest:
    - refresh: True
    - pkgs:
        - salt-master
        - salt-ssh

salt_master_service:
  cmd.run:
    - name: service salt-master restart

  {%- if pillar["salt"]["master"]["repo"] is defined %}
salt_master_deploy_repo:
  cmd.run:
    - name: |
        [ -d /srv/.git ] || ( cd /srv && git init . && ln -s ../../.githooks/post-merge .git/hooks/post-merge && git remote add origin {{ pillar["salt"]["master"]["repo"] }} && GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no" git pull origin master && GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no" git submodule init && GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no" git submodule update --recursive -f --checkout && git branch --set-upstream-to=origin/master master && .git/hooks/post-merge )

salt_master_update_repo:
  cmd.run:
    - name: |
        [ -d /srv/.git ] && ( cd /srv && GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no" git pull && GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no" git submodule sync && GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no" git submodule init && GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no" git submodule update -f --checkout && GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no" git submodule foreach "git checkout master && git pull" )
  {%- endif %}
  
  {%- if pillar["salt"]["master"]["gitlab-runner"] %}
# Should be unregistered before config update.
# Runners couldn't be unregistered without admin token or saving auth token.
# We don't want to expose gitlab admin token to client repo.
# So if salt master recreated from scratch - runner should be removed manually.
# Auto unregister works only on state re apply of alive master container.
salt_master_gitlab-runner_unregister:
  cmd.run:
    - name: |
        gitlab-runner unregister --url "{{ pillar["salt"]["master"]["gitlab-runner"]["gitlab_url"] }}/" --all-runners || true

salt_master_gitlab-runner_repo:
  pkgrepo.managed:
    - humanname: Gitlab Runner Repository
    - name: deb https://packages.gitlab.com/runner/gitlab-runner/{{ grains['os']|lower }}/ {{ grains['oscodename'] }} main
    - file: /etc/apt/sources.list.d/gitlab-runner.list
    - key_url: https://packages.gitlab.com/gpg.key
    - clean_file: True

# The following signatures were invalid: EXPKEYSIG 3F01618A51312F3F GitLab B.V. (package repository signing key) <packages@gitlab.com>
# even with previous state -> some bug workaround
salt_master_gitlab-runner_repo_key_hack:
  cmd.run:
    - name: "curl -s https://packages.gitlab.com/gpg.key | sudo apt-key add -"

salt_master_gitlab-runner_config_dir:
  file.directory:
    - name: /etc/gitlab-runner
    - user: root
    - group: root
    - mode: 700

    # Hack to set value inside for loop
    {%- set concurrent = {"value": salt["pillar.get"]("salt:master:gitlab-runner:concurrent", 16)|int} %}

    {%- if "salt-ssh" in pillar["salt"]["master"]["gitlab-runner"] %}
      {%- do concurrent.update({"value": concurrent["value"] + salt["pillar.get"]("salt:master:gitlab-runner:salt-ssh:concurrent", 16)|int}) %}
    {%- endif %}

    {%- if "additional_salt-ssh" in pillar["salt"]["master"]["gitlab-runner"] %}
      {%- for additional_runner in pillar["salt"]["master"]["gitlab-runner"]["additional_salt-ssh"] %}
        {%- do concurrent.update({"value": concurrent["value"] + additional_runner["concurrent"]|default(16)|int}) %}
      {%- endfor %}
    {%- endif %}

salt_master_gitlab-runner_config:
  file.managed:
    - name: /etc/gitlab-runner/config.toml
    - user: root
    - group: root
    - mode: 600
    - contents: |
        concurrent = {{ concurrent["value"] }}
        check_interval = 0
        
        [session_server]
          session_timeout = 1800

salt_master_gitlab-runner_sudoers:
  file.managed:
    - name: /etc/sudoers.d/gitlab-runner
    - user: root
    - group: root
    - mode: 440
    - contents: |
        gitlab-runner ALL=(ALL) NOPASSWD: /srv/scripts/ci_sudo/salt_master_pull.sh
        gitlab-runner ALL=(ALL) NOPASSWD: /srv/scripts/ci_sudo/salt_cmd.sh
        gitlab-runner ALL=(ALL) NOPASSWD: /srv/scripts/ci_sudo/count_alive_minions.sh
        gitlab-runner ALL=(ALL) NOPASSWD: /srv/scripts/ci_sudo/rsnapshot_backup_update_config.sh
        gitlab-runner ALL=(ALL) NOPASSWD: /srv/scripts/ci_sudo/rsnapshot_backup_sync.sh
        gitlab-runner ALL=(ALL) NOPASSWD: /srv/scripts/ci_sudo/rsnapshot_backup_rotate.sh
        gitlab-runner ALL=(ALL) NOPASSWD: /srv/scripts/ci_sudo/rsnapshot_backup_check_backup.sh
        gitlab-runner ALL=(ALL) NOPASSWD: /srv/scripts/ci_sudo/rsnapshot_backup_check_coverage.sh
        gitlab-runner ALL=(ALL) NOPASSWD: /srv/scripts/ci_sudo/refresh_pillar.sh
        gitlab-runner ALL=(ALL) NOPASSWD:SETENV: /srv/scripts/ci_sudo/send_notify_devilry.sh

salt_master_gitlab-runner_pkg:
  pkg.latest:
    - refresh: True
    - pkgs:
        - gitlab-runner
        - jq
        - curl

salt_master_gitlab-runner_register:
  cmd.run:
    - name: |
        gitlab-runner register --non-interactive --url "{{ pillar["salt"]["master"]["gitlab-runner"]["gitlab_url"] }}/" \
          --registration-token "{{ pillar["salt"]["master"]["gitlab-runner"]["registration_token"] }}" \
          --executor "shell" --name "{{ pillar["salt"]["master"]["gitlab-runner"]["gitlab_runner_name"] }}" \
          --tag-list "{{ pillar["salt"]["master"]["gitlab-runner"]["gitlab_runner_name"] }}" \
          --limit {{ pillar["salt"]["master"]["gitlab-runner"]["concurrent"]|default(16)|int }} \
          --locked --access-level "ref_protected" {{ "--output-limit " + pillar["salt"]["master"]["gitlab-runner"]["output_limit"]|string if pillar["salt"]["master"]["gitlab-runner"]["output_limit"] is defined else "" }}

    {%- if "salt-ssh" in pillar["salt"]["master"]["gitlab-runner"] %}
salt_master_gitlab-runner_register_salt-ssh:
  cmd.run:
    - name: |
        gitlab-runner register --non-interactive --url "{{ pillar["salt"]["master"]["gitlab-runner"]["gitlab_url"] }}/" \
          --registration-token "{{ pillar["salt"]["master"]["gitlab-runner"]["registration_token"] }}" \
          --executor "docker" --name "{{ pillar["salt"]["master"]["gitlab-runner"]["gitlab_runner_name"] }}_salt-ssh" \
          --tag-list "salt-ssh" \
          --limit {{ pillar["salt"]["master"]["gitlab-runner"]["salt-ssh"]["concurrent"]|default(16)|int }} \
          --locked --docker-privileged --docker-image 'docker:stable' --access-level "ref_protected" {{ "--output-limit " + pillar["salt"]["master"]["gitlab-runner"]["output_limit"]|string if pillar["salt"]["master"]["gitlab-runner"]["output_limit"] is defined else "" }}

    {%- endif %}

    {%- if "additional_salt-ssh" in pillar["salt"]["master"]["gitlab-runner"] %}
      {%- for additional_runner in pillar["salt"]["master"]["gitlab-runner"]["additional_salt-ssh"] %}
salt_master_gitlab-runner_register_additional_salt-ssh_{{ loop.index }}:
  cmd.run:
    - name: |
        gitlab-runner register --non-interactive --url "{{ pillar["salt"]["master"]["gitlab-runner"]["gitlab_url"] }}/" \
          --registration-token "{{ additional_runner["registration_token"] }}" \
          --executor "docker" --name "{{ pillar["salt"]["master"]["gitlab-runner"]["gitlab_runner_name"] }}_salt-ssh_{{ additional_runner["project"] }}" \
          --tag-list "salt-ssh" \
          --limit {{ additional_runner["concurrent"]|default(16)|int }} \
          --locked --docker-privileged --docker-image 'docker:stable' --access-level "ref_protected" {{ "--output-limit " + pillar["salt"]["master"]["gitlab-runner"]["output_limit"]|string if pillar["salt"]["master"]["gitlab-runner"]["output_limit"] is defined else "" }}

      {%- endfor %}
    {%- endif %}

salt_master_gitlab-runner_job_fail_on_clear_screen_fix:
  file.absent:
    - name: /home/gitlab-runner/.bash_logout

  {%- endif %}

{% endif %}
