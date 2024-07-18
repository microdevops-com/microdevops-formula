{% if pillar['redis'] is defined and 'redis_conf' in pillar['redis'] %}

  {%- if 'auth' in pillar['redis'] %}
auth file for cmd check alert:
  file.managed:
    - name: /root/.redis
    - contents: "AUTH={{ pillar['redis']['auth'] }}"
  {%- endif %}

inotify-tools install:
  pkg.latest:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - inotify-tools

redis_repo_keyringdir:
  file.directory:
    - name: /etc/apt/keyrings
    - user: root
    - group: root

redis_repo:
{% set opts  = {"listfile":"/etc/apt/sources.list.d/redislabs-ubuntu-redis.list",
                "keyfile":"/etc/apt/keyrings/redis.gpg",
                "keyid": '60A0586666DE0BA4B481628ACC59E6B43FA6E3CA'} %}
  pkg.installed:
    - pkgs:
      - gpg
  cmd.run:
    - name: |
    {% if grains['os'] == 'Debian' %}
        gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg <(curl -fsSL https://packages.redis.io/gpg)
    {% else %}
        {% if "keyid" in opts %}
        gpg --keyserver keyserver.ubuntu.com --recv-keys {{ opts["keyid"] }}
        gpg --batch --yes --no-tty --output {{ opts["keyfile"] }} --export {{ opts["keyid"] }}
        {% endif %}
    - creates: {{ opts["keyfile"] }}
    {% endif %}
  file.managed:
    - name: {{ opts["listfile"] }}
    - contents: |
    {% if grains['os'] == 'Debian' %}
        deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb {{ grains['oscodename'] }} main
    {% else %}
        deb [signed-by={{ opts["keyfile"] }}] https://ppa.launchpadcontent.net/redislabs/redis/ubuntu {{ grains['oscodename'] }} main
    {% endif %}

redis_install:
  pkg.latest:
    - refresh: True
    - reload_modules: True
    - pkgs:
    {% if grains['os'] == 'Debian' %}
        - redis
    {% else %}
        - redis-server
    {% endif %}

redis_run:
  service.running:
    - name: redis-server
    - enable: True

  {%- if not pillar['redis'].get('keep_existing_conf', True) %}
redis_config:
  file.managed:
    - name: /etc/redis/redis.conf
    - user: 0
    - group: 0
    - mode: 644
    - contents: {{ pillar['redis']['redis_conf'] | yaml_encode }}

redis_restart:
  cmd.run:
    - name: systemctl restart redis-server
    - onchanges:
        - file: /etc/redis/redis.conf
  {%- endif %}

  {%- if pillar['redis'].get('disable_thp', False) %}
disable_transparent_hugepage:
  cmd.run:
    - name: 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
    - shell: /bin/bash
  file.managed:
    - name: /etc/tmpfiles.d/dislable-thp.conf
    - contents: |
        #    Path                                            Mode UID  GID  Age Argument
        w    /sys/kernel/mm/transparent_hugepage/enabled     -    -    -    -   never
    - mode: 644
    - user: 0
    - group: 0
  {%- endif  %}

  {%- if pillar['redis'].get('manage_limits', False) %}
set_maxclients_for_redis_user:
  file.managed:
    - name: /etc/security/limits.d/95-redis.conf
    - user: 0
    - group: 0
    - mode: 644
    - contents: |
        root soft nofile {{ pillar['redis'].get('maxclients',10000) }}
        root hard nofile {{ pillar['redis'].get('maxclients',10000) }}
        redis soft nofile {{ pillar['redis'].get('maxclients', 10000) }}
        redis hard nofile {{ pillar['redis'].get('maxclients', 10000) }}
        haproxy soft nofile {{ pillar['redis'].get('maxclients',10000) * 2 + 100 }}
        haproxy hard nofile {{ pillar['redis'].get('maxclients',10000) * 2 + 100 }}
  {%- endif  %}
{% endif  %}
