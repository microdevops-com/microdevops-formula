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
        percona-release enable valkey release
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
    - user: valkey
    - group: valkey
    - recurse:
      - user
      - group
      - mode

percona_valkey_logfile:
  file.managed:
    - name: /var/log/valkey/valkey.log
    - user: valkey
    - group: valkey
    - mode: 644
    - replace: False
    - require:
      - file: percona_valkey_dirs

percona_valkey_run:
  service.running:
    - name: valkey
    - enable: True

  {%- if not pillar['percona-valkey'].get('keep_existing_conf', True) %}
percona_valkey_config:
  file.managed:
    - name: /etc/valkey/valkey.conf
    - user: 0
    - group: 0
    - mode: 644
    - contents: {{ pillar['percona-valkey']['valkey_conf'] | yaml_encode }}

percona_valkey_restart:
  cmd.run:
    - name: systemctl restart valkey
    - onchanges:
        - file: /etc/valkey/valkey.conf
  {%- endif %}

  {%- if pillar['percona-valkey'].get('disable_thp', False) %}
disable_transparent_hugepage:
  cmd.run:
    - name: 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
    - shell: /bin/bash
  file.managed:
    - name: /etc/tmpfiles.d/disable-thp.conf
    - contents: |
        #    Path                                            Mode UID  GID  Age Argument
        w    /sys/kernel/mm/transparent_hugepage/enabled     -    -    -    -   never
    - mode: 644
    - user: 0
    - group: 0
  {%- endif  %}

  {%- if pillar['percona-valkey'].get('manage_limits', False) %}
set_maxclients_for_valkey_user:
  file.managed:
    - name: /etc/security/limits.d/95-valkey.conf
    - user: 0
    - group: 0
    - mode: 644
    - contents: |
        root soft nofile {{ pillar['percona-valkey'].get('maxclients',10000) }}
        root hard nofile {{ pillar['percona-valkey'].get('maxclients',10000) }}
        valkey soft nofile {{ pillar['percona-valkey'].get('maxclients', 10000) }}
        valkey hard nofile {{ pillar['percona-valkey'].get('maxclients', 10000) }}
        haproxy soft nofile {{ pillar['percona-valkey'].get('maxclients',10000) * 2 + 100 }}
        haproxy hard nofile {{ pillar['percona-valkey'].get('maxclients',10000) * 2 + 100 }}
  {%- endif  %}
{% endif  %}
