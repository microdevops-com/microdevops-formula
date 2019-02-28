{% if pillar['sysadmws-utils'] is defined and pillar['sysadmws-utils'] is not none %}
  {%- if (pillar['sysadmws-utils']['v0'] is defined and pillar['sysadmws-utils']['v0'] is not none and pillar['sysadmws-utils']['v0']|lower == "latest") or
         (pillar['sysadmws-utils']['v1'] is defined and pillar['sysadmws-utils']['v1'] is not none and pillar['sysadmws-utils']['v1']|lower == "latest")
   %}

    {%- if grains['oscodename'] == "precise" %}
pkgrepo_precise_backports:
  pkgrepo.managed:
    - file: /etc/apt/sources.list.d/precise-backports.list
    - name: 'deb http://de.archive.ubuntu.com/ubuntu/ precise-backports main restricted universe multiverse'
    - refresh: True
    {%- endif %}

    {%- if grains['os'] in ['Ubuntu', 'Debian'] and not grains['oscodename'] in ['karmic'] %}
pkgrepo_sysadmws:
  pkgrepo.managed:
    - file: /etc/apt/sources.list.d/sysadmws.list
    - name: 'deb https://repo.sysadm.ws/sysadmws-apt/ any main'
    - keyid: 2E7DCF8C
    - keyserver: keyserver.ubuntu.com

pkg_latest_utils:
  pkg.latest:
    - refresh: True
    - pkgs:
      {%- if pillar['sysadmws-utils']['v0'] is defined and pillar['sysadmws-utils']['v0'] is not none and pillar['sysadmws-utils']['v0']|lower == "latest" %}
        - sysadmws-utils
      {%- endif %}
      {%- if pillar['sysadmws-utils']['v1'] is defined and pillar['sysadmws-utils']['v1'] is not none and pillar['sysadmws-utils']['v1']|lower == "latest" %}
        - sysadmws-utils-v1
      {%- endif %}

    {%- else %}
      {%- if grains['osfinger'] in ['CentOS-6'] %}
install_utils_deps_centos:
  pkg.installed:
    - pkgs:
        - python34
        - python34-PyYAML
        - python34-jinja2
      {%- endif %}

      {%- if grains['oscodename'] in ['karmic'] %}
install_utils_deps_karmic:
  pkg.installed:
    - pkgs:
        - python2.6
        - python-jinja2
        - python-yaml
      {%- endif %}

      {%- if pillar['sysadmws-utils']['v0'] is defined and pillar['sysadmws-utils']['v0'] is not none and pillar['sysadmws-utils']['v0']|lower == "latest" %}
install_utils_tgz_v0_1:
  cmd.run:
    - name: 'rm -f /root/sysadmws-utils.tar.gz'
    - runas: 'root'

install_utils_tgz_v0_2:
  cmd.run:
    - name: 'cd /root && wget --no-check-certificate https://repo.sysadm.ws/tgz/sysadmws-utils.tar.gz'
    - runas: 'root'

install_utils_tgz_v0_3:
  cmd.run:
    - name: 'tar zxf /root/sysadmws-utils.tar.gz -C /'
    - runas: 'root'

        {%- if grains['osfinger'] in ['CentOS-6'] %}
install_utils_tgz_v0_4:
  cmd.run:
    - name: 'sed -i "1s_.*_#!/usr/bin/python3.4_" /opt/sysadmws-utils/notify_devilry/notify_devilry.py'
    - runas: 'root'
        {%- endif %}

      {%- endif %}

      {%- if pillar['sysadmws-utils']['v1'] is defined and pillar['sysadmws-utils']['v1'] is not none and pillar['sysadmws-utils']['v1']|lower == "latest" %}
install_utils_tgz_v1_1:
  cmd.run:
    - name: 'rm -f /root/sysadmws-utils-v1.tar.gz'
    - runas: 'root'

install_utils_tgz_v1_2:
  cmd.run:
    - name: 'cd /root && wget --no-check-certificate https://repo.sysadm.ws/tgz/sysadmws-utils-v1.tar.gz'
    - runas: 'root'

install_utils_tgz_v1_3:
  cmd.run:
    - name: 'tar zxf /root/sysadmws-utils-v1.tar.gz -C /'
    - runas: 'root'

        {%- if grains['osfinger'] in ['CentOS-6'] %}
install_utils_tgz_v1_4:
  cmd.run:
    - name: 'sed -i "1s_.*_#!/usr/bin/python3.4_" /opt/sysadmws/notify_devilry/notify_devilry.py'
    - runas: 'root'
        {%- endif %}

      {%- endif %}
    {%- endif %}
  {%- endif %}

  {%- if pillar['sysadmws-utils']['v0'] is defined and pillar['sysadmws-utils']['v0'] is not none and pillar['sysadmws-utils']['v0']|lower == "purged" %}
    {%- if grains['os'] in ['Ubuntu', 'Debian'] and not grains['oscodename'] in ['karmic'] %}

pkg_purged_utils:
  pkg.purged:
    - name: sysadmws-utils

    {%- endif %}

# For all OS final clean
rm_utils_v0_1:
  file.absent:
    - name: /root/sysadmws-utils.tar.gz

rm_utils_v0_2:
  file.absent:
    - name: /opt/sysadmws-utils

rm_utils_v0_3:
  file.absent:
    - name: /etc/cron.d/sysadmws-rsnapshot-backup

  {%- endif %}

{% else %}
sysadmws-utils_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured for a minion of this type, so nothing has been done. But it is OK.
{% endif %}
