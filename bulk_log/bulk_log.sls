{% if pillar['bulk_log'] is defined and pillar['bulk_log'] is not none and pillar['bulk_log']['enabled'] is defined and pillar['bulk_log']['enabled'] is not none and pillar['bulk_log']['enabled'] %}

  {%- if salt['file.directory_exists']('/opt/sysadmws/bulk_log') %}
swsu_v1_bulk_log_cron_managed:
  cron.present:
    - name: '/opt/sysadmws/bulk_log/bulk_log.sh >> /opt/sysadmws/bulk_log/bulk_log.log'
    - identifier: 'sysadmws_bulk_log'
    - user: root
    - minute: '*/2'
  {%- endif %}

{% endif %}
