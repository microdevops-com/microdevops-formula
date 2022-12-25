{% if pillar["microdevops-utils"] is defined and "version" in pillar["microdevops-utils"] and pillar["microdevops-utils"]["version"] == "latest" %}

  {%- if grains["os"] in ["Ubuntu", "Debian"] and grains["oscodename"] != "precise" %}
microdevops-utils_pkgrepo_sysadmws:
  pkgrepo.managed:
    - file: /etc/apt/sources.list.d/sysadmws.list
    - name: "deb https://repo.sysadm.ws/sysadmws-apt/ any main"
    - keyid: 2E7DCF8C
    - keyserver: keyserver.ubuntu.com
    {%- if grains["osarch"] in ["arm64"] %}
    - architectures: amd64
    {%- endif %}

microdevops-utils_pkg_latest_utils:
  pkg.latest:
    - refresh: True
    - pkgs:
        - sysadmws-utils-v1

  {%- else %}
microdevops-utils_sysadmws_dir:
  file.directory:
    - name: /opt/sysadmws

microdevops-utils_microdevops_dir:
  file.directory:
    - name: /opt/microdevops

# Curl to tar extract without temp files
# On old systems, with ssl/tls errors, you can use static binary curl from https://github.com/moparisthebest/static-curl
microdevops-utils_install_from_tar_gz:
  cmd.run:
    - name: curl -L https://repo.sysadm.ws/tgz/sysadmws-utils-v1.tar.gz | tar -xz -C /opt --strip-components=2

  {%- endif %}

# Run cleanup
microdevops-utils_cleanup:
  cmd.run:
    - name: /opt/microdevops/misc/cleanup.sh

# Install requirmenets
microdevops-utils_install_requirements:
  cmd.run:
    - name: /opt/microdevops/misc/install_requirements.sh

{% else %}
microdevops-utils_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured for a minion of this type, so nothing has been done. But it is OK.

{% endif %}
