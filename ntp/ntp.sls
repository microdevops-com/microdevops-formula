{% if pillar['ntp'] is defined and pillar['ntp'] is not none and 'sync_type' in pillar['ntp'] and pillar['ntp']['sync_type'] == 'ntpdate_unprivileged_cron' %}
ntp_ntpdate_installed:
  pkg.installed:
    - pkgs:
      - ntpdate

ntp_ntpdate_cron:
  cron.present:
    - name: '/usr/sbin/ntpdate -s -v -u us.pool.ntp.org'
    - identifier: 'ntpdate_unprivileged_cron'
    - user: root
    - minute: '*/15'

{% endif %}

{% if grains['virtual'] == 'physical' and grains['oscodename'] not in ['focal'] %}
ntp_service_installed:
  pkg.installed:
    - pkgs:
      - ntp

ntp_service_running:
  service.running:
    {%- if grains['os'] in ['CentOS', 'RedHat'] %}
    - name: ntpd
    {%- else %}
    - name: ntp
    {%- endif %}
    - enable: True

{% else %}
ntp_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state has nothing to do. But it is OK.

{% endif %}
