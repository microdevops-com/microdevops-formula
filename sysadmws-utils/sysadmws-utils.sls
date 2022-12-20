{% if pillar["sysadmws-utils"] is defined and "v1" in pillar["sysadmws-utils"] and pillar["sysadmws-utils"]["v1"]|lower == "latest" %}

  {%- if grains["os"] in ["Ubuntu", "Debian"] and grains["oscodename"] != "precise" %}
pkgrepo_sysadmws:
  pkgrepo.managed:
    - file: /etc/apt/sources.list.d/sysadmws.list
    - name: "deb https://repo.sysadm.ws/sysadmws-apt/ any main"
    - keyid: 2E7DCF8C
    - keyserver: keyserver.ubuntu.com
    {%- if grains["osarch"] in ["arm64"] %}
    - architectures: amd64
    {%- endif %}

pkg_latest_utils:
  pkg.latest:
    - refresh: True
    - pkgs:
        - sysadmws-utils-v1

  {%- else %}
microdevops_utils_sysadmws_dir:
  file.directory:
    - name: /opt/sysadmws

microdevops_utils_microdevops_dir:
  file.directory:
    - name: /opt/microdevops

# Curl to tar extract without temp files
# On old systems, with ssl/tls errors, you can use static binary curl from https://github.com/moparisthebest/static-curl
microdevops_utils_install_from_tar_gz:
  cmd.run:
    - name: curl -L https://repo.sysadm.ws/tgz/sysadmws-utils-v1.tar.gz | tar -xz -C /opt --strip-components=2

  {%- endif %}

install_requirements_v1:
  cmd.run:
    - name: /opt/sysadmws/misc/install_requirements.sh

{% else %}
sysadmws-utils_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured for a minion of this type, so nothing has been done. But it is OK.

{% endif %}
