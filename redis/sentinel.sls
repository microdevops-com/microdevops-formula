{% if pillar['redis']['sentinel_conf'] is defined %}
redis_install:
  pkgrepo.managed:
    - ppa: redislabs/redis
  pkg.latest:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - redis-sentinel

redis_config:
  file.managed:
    - name: /etc/redis/sentinel.conf
    - user: 0
    - group: 0
    - mode: 644
    - contents: {{ pillar['redis']['sentinel_conf'] | yaml_encode }}

redis_run:
  service.running:
    - name: redis-sentinel
    - enable: True

redis_restart:
  cmd.run:
    - name: systemctl restart redis-sentinel
    - onchanges:
        - file: /etc/redis/sentinel.conf
{% endif  %}
