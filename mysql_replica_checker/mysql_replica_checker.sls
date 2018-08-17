{% if pillar['mysql_replica_checker'] is defined and pillar['mysql_replica_checker'] is not none %}

  {%- if salt['file.directory_exists']('/opt/sysadmws-utils/mysql_replica_checker') %}
swsu_v0_mysql_replica_checker_config_managed:
  file.managed:
    - name: '/opt/sysadmws-utils/mysql_replica_checker/mysql_replica_checker.conf'
    - mode: 0644
    - user: root
    - group: root
    - contents: {{ pillar['mysql_replica_checker'] | yaml_encode }}
  {%- endif %}

  {%- if salt['file.directory_exists']('/opt/sysadmws/mysql_replica_checker') %}
swsu_v1_mysql_replica_checker_config_managed:
  file.managed:
    - name: '/opt/sysadmws/mysql_replica_checker/mysql_replica_checker.conf'
    - mode: 0644
    - user: root
    - group: root
    - contents: {{ pillar['mysql_replica_checker'] | yaml_encode }}
  {%- endif %}

{% endif %}
