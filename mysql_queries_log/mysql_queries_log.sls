{% if pillar['mysql_queries_log'] is defined and pillar['mysql_queries_log'] is not none and pillar['mysql_queries_log']['enabled'] is defined and pillar['mysql_queries_log']['enabled'] is not none and pillar['mysql_queries_log']['enabled'] %}

  {%- if salt['file.directory_exists']('/opt/sysadmws/mysql_queries_log') %}
swsu_v1_mysql_queries_log_cron_managed:
  cron.present:
    - name: '/opt/sysadmws/mysql_queries_log/mysql_queries_log.sh >> /opt/sysadmws/mysql_queries_log/mysql_queries_log.log 2>&1'
    - identifier: mysql_queries_log
    - user: root
    - minute: '*'

swsu_v1_mysql_queries_log_logrotate:
  file.managed:
    - name: /etc/logrotate.d/mysql_queries_log
    - user: root
    - group: root
    - mode: 600
    - source: /opt/sysadmws/mysql_queries_log/mysql_queries_log.logrotate
  {%- endif %}

{% endif %}
