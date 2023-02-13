{% if pillar['redis'] is defined and not 'sentinel_conf' in pillar['redis'] %}

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

redis_install:
  pkgrepo.managed:
    - ppa: redislabs/redis
  pkg.latest:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - redis-server

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
