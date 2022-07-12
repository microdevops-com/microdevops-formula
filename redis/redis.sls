{% if pillar['redis']['redis_conf'] %}
redis_install:
  pkgrepo.managed:
    - ppa: redislabs/redis
  pkg.latest:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - redis-server

redis_config:
  file.managed:
    - name: /etc/redis/redis.conf
    - user: 0
    - group: 0
    - mode: 644
    - contents: {{ pillar['redis']['redis_conf'] | yaml_encode }}

redis_run:
  service.running:
    - name: redis-server
    - enable: True

redis_restart:
  cmd.run:
    - name: systemctl restart redis-server
    - onchanges:
        - file: /etc/redis/redis.conf
{% endif  %}
