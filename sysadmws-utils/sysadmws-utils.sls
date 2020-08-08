{% if pillar["sysadmws-utils"] is defined and pillar["sysadmws-utils"] is not none and "v1" in pillar["sysadmws-utils"] and pillar["sysadmws-utils"]["v1"]|lower == "latest" %}

  {%- if grains["oscodename"] == "precise" %}
pkgrepo_precise_backports:
  pkgrepo.managed:
    - file: /etc/apt/sources.list.d/precise-backports.list
    - name: "deb http://de.archive.ubuntu.com/ubuntu/ precise-backports main restricted universe multiverse"
    - refresh: True
  {%- endif %}

  {%- if grains["os"] in ["Ubuntu", "Debian"] %}
pkgrepo_sysadmws:
  pkgrepo.managed:
    - file: /etc/apt/sources.list.d/sysadmws.list
    - name: "deb https://repo.sysadm.ws/sysadmws-apt/ any main"
    - keyid: 2E7DCF8C
    - keyserver: keyserver.ubuntu.com

pkg_latest_utils:
  pkg.latest:
    - refresh: True
    - pkgs:
        - sysadmws-utils-v1

  {%- else %}
install_utils_tgz_v1_1:
  cmd.run:
    - name: "rm -f /root/sysadmws-utils-v1.tar.gz"
    - runas: "root"

install_utils_tgz_v1_2:
  cmd.run:
    - name: "cd /root && wget --no-check-certificate https://repo.sysadm.ws/tgz/sysadmws-utils-v1.tar.gz"
    - runas: "root"

install_utils_tgz_v1_3:
  cmd.run:
    - name: "tar zxf /root/sysadmws-utils-v1.tar.gz -C /"
    - runas: "root"

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
