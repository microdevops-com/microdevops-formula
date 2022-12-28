{% if pillar["gitlab-runner"] is defined %}
gitlab-runner_repo:
  pkgrepo.managed:
    - humanname: Gitlab Runner Repository
    # TODO no jammy packages yet
    - name: deb https://packages.gitlab.com/runner/gitlab-runner/{{ grains['os']|lower }}/ {{ "focal" if grains["oscodename"] in ["jammy"] else grains["oscodename"] }} main
    - file: /etc/apt/sources.list.d/gitlab-runner.list
    - key_url: https://packages.gitlab.com/gpg.key
    - clean_file: True

# The following signatures were invalid: EXPKEYSIG 3F01618A51312F3F GitLab B.V. (package repository signing key) <packages@gitlab.com>
# even with previous state -> some bug workaround
gitlab-runner_repo_key_hack:
  cmd.run:
    - name: "curl -s https://packages.gitlab.com/gpg.key | sudo apt-key add -"

gitlab-runner_pkg:
  pkg.latest:
    - refresh: True
    - pkgs:
      - gitlab-runner
      - jq
      - curl

  {%- if "docker_group" in pillar["gitlab-runner"] and pillar["gitlab-runner"]["docker_group"] %}
gitlab-runner_add_docker:
  user.present:
    - name: gitlab-runner
    - groups:
      - docker

  {%- endif %}

gitlab-runner_unregister:
  cmd.run:
    - name: |
        gitlab-runner unregister --name "{{ pillar["gitlab-runner"]["name"] }}" || true

gitlab-runner_config:
  file.managed:
    - name: /etc/gitlab-runner/config.toml
    - contents: |
        concurrent = {{ pillar["gitlab-runner"]["concurrency"] }}
        check_interval = 0
        shutdown_timeout = 0
        
        [session_server]
          session_timeout = 1800

# https://docs.gitlab.com/runner/shells/index.html#shell-profile-loading
gitlab-runner_bash_issue_fix:
  file.absent:
    - name: /home/gitlab-runner/.bash_logout

gitlab-runner_register:
  cmd.run:
    - name: |
        gitlab-runner register \
          --non-interactive \
          --url "{{ pillar["gitlab-runner"]["gitlab"]["url"] }}" \
          --registration-token "{{ pillar["gitlab-runner"]["gitlab"]["registration_token"] }}" \
          --executor "{{ pillar["gitlab-runner"]["executor"] }}" \
          --name "{{ pillar["gitlab-runner"]["name"] }}" \
          --tag-list "{{ pillar["gitlab-runner"]["tags"] }}" \
          {{ pillar["gitlab-runner"]["register_opts"] }}

  {%- for project in pillar["gitlab-runner"]["projects"] %}
gitlab-runner_project_{{ loop.index }}:
  cmd.run:
    - name: |
        RUNNER_ID=$(curl --silent --header "PRIVATE-TOKEN: {{ pillar["gitlab-runner"]["gitlab"]["admin_token"] }}" "{{ pillar["gitlab-runner"]["gitlab"]["url"] }}/api/v4/runners/all?tag_list={{ pillar["gitlab-runner"]["tags"] }}" | jq '.[] | select(.description=="{{ pillar["gitlab-runner"]["name"] }}") | .id') \
          && curl --silent --request POST --header "PRIVATE-TOKEN: {{ pillar["gitlab-runner"]["gitlab"]["admin_token"] }}" \
          "{{ pillar["gitlab-runner"]["gitlab"]["url"] }}/api/v4/projects/{{ project | replace("/","%2F") }}/runners" --form "runner_id=${RUNNER_ID}"
    - shell: /bin/bash

  {%- endfor %}

  {%- if "keys" in pillar["gitlab-runner"] %}
gitlab-runner_ssh_dir:
  file.directory:
    - name: /home/gitlab-runner/.ssh
    - user: gitlab-runner
    - group: gitlab-runner
    - mode: 0700

    {%- for key_name, key_params in pillar["gitlab-runner"]["keys"].items() %}
gitlab-runner_ssh_key_priv_{{ loop.index }}:
  file.managed:
    - name: /home/gitlab-runner/.ssh/{{ key_name }}
    - user: gitlab-runner
    - group: gitlab-runner
    - mode: 0600
    - contents: {{ key_params["priv"] | yaml_encode }}

gitlab-runner_ssh_key_pub_{{ loop.index }}:
  file.managed:
    - name: /home/gitlab-runner/.ssh/{{ key_name }}.pub
    - user: gitlab-runner
    - group: gitlab-runner
    - mode: 0644
    - contents: {{ key_params["pub"] | yaml_encode }}

    {%- endfor %}

  {%- endif %}

{% endif %}
