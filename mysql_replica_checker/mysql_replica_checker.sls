{% if pillar['mysql_replica_checker'] is defined and pillar['mysql_replica_checker'] is not none and pillar['mysql_replica_checker']['enabled'] is defined and pillar['mysql_replica_checker']['enabled'] is not none and pillar['mysql_replica_checker']['enabled'] %}

  {%- if salt['file.directory_exists']('/opt/sysadmws-utils/mysql_replica_checker') %}
    {%- if pillar['mysql_replica_checker']['config'] is defined and pillar['mysql_replica_checker']['config'] is not none %}
swsu_v0_mysql_replica_checker_config_managed:
  file.managed:
    - name: '/opt/sysadmws-utils/mysql_replica_checker/mysql_replica_checker.conf'
    - mode: 0644
    - user: root
    - group: root
    - contents: {{ pillar['mysql_replica_checker']['config'] | yaml_encode }}
    {%- endif %}
  {%- endif %}

  {%- if salt['file.directory_exists']('/opt/sysadmws/mysql_replica_checker') %}
    {%- if pillar['mysql_replica_checker']['config'] is defined and pillar['mysql_replica_checker']['config'] is not none %}
swsu_v1_mysql_replica_checker_config_managed:
  file.managed:
    - name: '/opt/sysadmws/mysql_replica_checker/mysql_replica_checker.conf'
    - mode: 0644
    - user: root
    - group: root
    - contents: {{ pillar['mysql_replica_checker']['config'] | yaml_encode }}
    {%- endif %}

swsu_v1_mysql_replica_checker_cron_managed:
  cron.present:
    - name: '/opt/sysadmws/mysql_replica_checker/mysql_replica_checker.sh'
    - identifier: mysql_replica_checker
    - user: root
    - minute: '*/30'
  {%- endif %}

{% endif %}
