{% if pillar["microdevops-utils"] is defined and "version" in pillar["microdevops-utils"] and pillar["microdevops-utils"]["version"] == "latest" %}

  {%- if grains["os"] in ["Ubuntu", "Debian"] and grains["oscodename"] not in ["precise", "trusty"] %}

microdevops-utils_repo_sysadmws_keyringdir:
  file.directory:
    - name: /etc/apt/keyrings
    - user: root
    - group: root

microdevops-utils_repo_sysadmws_keyringfile:
  file.managed:
    - name: /etc/apt/keyrings/sysadmws.gpg
    - source: salt://microdevops-utils/files/sysadmws.gpg

microdevops-utils_repo_sysadmws_listfile:
  file.managed:
    - name: /etc/apt/sources.list.d/sysadmws.list
    - contents: |
        deb [arch=amd64 signed-by=/etc/apt/keyrings/sysadmws.gpg] https://repo.sysadm.ws/sysadmws-apt/ any main

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

  {%- if "force_python" in pillar["microdevops-utils"] %}
microdevops-utils_shebang_python_switcher:
  file.managed:
    - name: /opt/microdevops/misc/shebang_python_switcher.conf
    - contents: {{ pillar["microdevops-utils"]["force_python"] | yaml_dquote }}

  {%- endif %}

{% else %}
microdevops-utils_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured for a minion of this type, so nothing has been done. But it is OK.

{% endif %}
