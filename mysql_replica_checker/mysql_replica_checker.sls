{% if pillar["mysql_replica_checker"] is defined and "enabled" in pillar["mysql_replica_checker"] and pillar["mysql_replica_checker"]["enabled"] %}

  {%- if salt["file.directory_exists"]("/opt/sysadmws/mysql_replica_checker") %}
    {%- if "config" in pillar["mysql_replica_checker"] %}
swsu_v1_mysql_replica_checker_config_managed:
  file.managed:
    - name: /opt/sysadmws/mysql_replica_checker/mysql_replica_checker.conf
    - mode: 0644
    - user: root
    - group: root
    - contents: {{ pillar["mysql_replica_checker"]["config"] | yaml_encode }}
    {%- endif %}

swsu_v1_mysql_replica_checker_cron_managed:
  cron.present:
    - name: /opt/sysadmws/mysql_replica_checker/mysql_replica_checker.sh
    - identifier: mysql_replica_checker
    - user: root
    - minute: '*/30'
    {%- if "cron_disabled" in pillar["mysql_replica_checker"] and pillar["mysql_replica_checker"]["cron_disabled"] %}
    - commented: True
    {%- endif %}
  {%- endif %}

{% else %}
mysql_replica_checker_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured for a minion of this type, so nothing has been done. But it is OK.
{% endif %}
