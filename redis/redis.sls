{%- if pillar['redis']['redis_conf'] is defined %}
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

  {%- if not pillar['redis']['keep_existing_conf'] | default(False) %}
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

  {%- if pillar['redis']['disable_thp'] | default(True) %}
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
set_maxclients_for_redis_user:
  file.managed:
    - name: /etc/security/limits.d/95-redis.conf
    - user: 0
    - group: 0
    - mode: 644
    - contents: |
        redis soft nofile {{ pillar['redis']['maxclients'] | default(10000) }}
        redis hard nofile {{ pillar['redis']['maxclients'] | default(10000) }}
{%- endif  %}
