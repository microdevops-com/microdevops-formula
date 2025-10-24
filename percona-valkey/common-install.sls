{% if pillar['percona-valkey'] is defined and 'valkey_conf' in pillar['percona-valkey'] %}

  {%- if 'auth' in pillar['percona-valkey'] %}
auth file for cmd check alert:
  file.managed:
    - name: /root/.valkey
    - contents: "AUTH={{ pillar['percona-valkey']['auth'] }}"
  {%- endif %}

inotify-tools install:
  pkg.latest:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - inotify-tools

valkey_repo_keyringdir:
  file.directory:
    - name: /etc/apt/keyrings
    - user: root
    - group: root

percona_valkey_repo:
{% if grains['os_family'] == 'Debian' %}
  pkg.installed:
    - pkgs:
      - gnupg2
      - curl
      - lsb-release
  cmd.run:
    - name: |
        curl -O https://repo.percona.com/apt/percona-release_latest.generic_all.deb
        dpkg -i percona-release_latest.generic_all.deb
        percona-release enable valkey experimental
        apt-get update
    - cwd: /tmp
    - unless: test -f /etc/apt/sources.list.d/percona-valkey-release.list
{% else %}
  pkg.installed:
    - pkgs:
      - gnupg2
      - curl
  cmd.run:
    - name: |
        yum install -y https://repo.percona.com/yum/percona-release-latest.noarch.rpm
        percona-release enable valkey experimental
        yum update -y
    - unless: test -f /etc/yum.repos.d/percona-valkey-release.repo
{% endif %}

percona_valkey_install:
  pkg.latest:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - valkey

percona_valkey_dirs:
  file.directory:
    - names:
      - /var/lib/valkey
      - /var/log/valkey
      - /etc/valkey
    - user: valkey
    - group: valkey
    - recurse:
      - user
      - group
{% endif  %}
