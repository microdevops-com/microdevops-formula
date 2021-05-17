{% if pillar["sysadmws-utils"] is defined and "v1" in pillar["sysadmws-utils"] and pillar["sysadmws-utils"]["v1"]|lower == "latest" %}

  {%- if grains["os"] in ["Ubuntu", "Debian"] and grains["oscodename"] != "precise" %}
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
install_utils_tgz_v1_0:
  file.directory:
    - name: /opt/sysadmws
    - user: root
    - group: root
    - mode: 0775

install_utils_tgz_v1_1:
  cmd.run:
    - name: rm -f /root/sysadmws-utils-v1.tar.gz
    - runas: root

install_utils_tgz_v1_2:
  cmd.run:
    - name: cd /root && wget --no-check-certificate https://repo.sysadm.ws/tgz/sysadmws-utils-v1.tar.gz
    - runas: root

install_utils_tgz_v1_3:
  cmd.run:
    - name: tar zxf /root/sysadmws-utils-v1.tar.gz --strip-components=3 -C /opt/sysadmws
    - runas: root

  {%- endif %}

install_requirements_v1:
  cmd.run:
    - name: /opt/sysadmws/misc/install_requirements.sh
    - runas: root

{% else %}
sysadmws-utils_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured for a minion of this type, so nothing has been done. But it is OK.

{% endif %}
