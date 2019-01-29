{% if pillar['ntp'] is defined and pillar['ntp'] is not none and pillar['ntp']['sync_type'] is defined and pillar['ntp']['sync_type'] is not none and pillar['ntp']['sync_type'] == 'ntpdate_unprivileged_cron' %}
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

{% else %}
  {%- if (grains['virtual_subtype'] is not defined or grains['virtual_subtype'] != 'LXC') and (grains['virtual'] is not defined or grains['virtual'] != 'LXC') %}

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

  {%- else %}
nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured by pillar, so nothing has been done. But it is OK.
  {%- endif %}

{% endif %}
