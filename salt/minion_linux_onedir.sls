{% if pillar["salt"] is defined and "minion" in pillar["salt"] and grains["os"] in ["Ubuntu", "Debian"] and pillar["salt"]["minion"]["version"]|int in [3006, 3007] %}

  {% set install_root = "" %}

salt_minion_dirs_1:
  file.directory:
    - names:
      - {{ install_root }}/etc/salt
      - {{ install_root }}/etc/salt/pki
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

salt_minion_dirs_2:
  file.directory:
    - names:
      - {{ install_root }}/etc/salt/pki/minion
    - user: root
    - group: root
    - mode: 700

  {%- if pillar["salt"]["minion"]["grains_file_rm"] is defined and pillar["salt"]["minion"]["grains_file_rm"] %}
salt_minion_grains_file_rm:
  file.absent:
    - name: {{ install_root }}/etc/salt/grains
  {%- endif %}

salt_minion_id:
  file.managed:
    - name: {{ install_root }}/etc/salt/minion_id
    - contents: |
        {{ grains["id"] }}

salt_minion_config:
  file.serialize:
    - name: {{ install_root }}/etc/salt/minion
    - user: root
    - group: root
    - mode: 644
    - show_changes: True
    - create: True
    - merge_if_exists: False
    - formatter: yaml
    - dataset: {{ pillar["salt"]["minion"]["config"] }}

  {%- if "pki" in pillar["salt"]["minion"] and "minion" in pillar["salt"]["minion"]["pki"] %}
salt_minion_pki_minion_pem:
  file.managed:
    - name: {{ install_root }}/etc/salt/pki/minion/minion.pem
    - user: root
    - group: root
    - mode: 400
    - contents: {{ pillar["salt"]["minion"]["pki"]["minion"]["pem"] | yaml_encode }}

salt_minion_pki_minion_pub:
  file.managed:
    - name: {{ install_root }}/etc/salt/pki/minion/minion.pub
    - user: root
    - group: root
    - mode: 644
    - contents: {{ pillar["salt"]["minion"]["pki"]["minion"]["pub"] | yaml_encode }}

salt_minion_pki_master_sign_pub:
  file.managed:
    - name: {{ install_root }}/etc/salt/pki/minion/master_sign.pub
    - user: root
    - group: root
    - mode: 644
    - contents: {{ pillar["salt"]["minion"]["pki"]["master_sign"] | yaml_encode }}

    {%- if "minion_master" in pillar["salt"]["minion"]["pki"] %}
salt_minion_pki_minion_master_pub:
  file.managed:
    - name: {{ install_root }}/etc/salt/pki/minion/minion_master.pub
    - user: root
    - group: root
    - mode: 644
    - contents: {{ pillar["salt"]["minion"]["pki"]["minion_master"] | yaml_encode }}

    {%- endif %}
  {%- endif %}

salt_minion_repo_key:
  file.managed:
    - name: /etc/apt/keyrings/salt-archive-keyring-2023.gpg
    - source: https://repo.saltproject.io/salt/py3/{{ grains["os"]|lower }}/{{ grains["osrelease"]|string }}/{{ grains["osarch"] }}/SALT-PROJECT-GPG-PUBKEY-2023.gpg
    - skip_verify: True

salt_minion_repo_list:
  file.managed:
    - name: /etc/apt/sources.list.d/saltstack.list
    - contents: |
        deb [signed-by=/etc/apt/keyrings/salt-archive-keyring-2023.gpg arch={{ grains["osarch"] }}] https://repo.saltproject.io/salt/py3/{{ grains["os"]|lower }}/{{ grains["osrelease"]|string }}/{{ grains["osarch"] }}/{{ pillar["salt"]["minion"]["version"]|string }} {{ grains["oscodename"] }} main

  {%- set salt_minion_version = pillar["salt"]["minion"]["version"]|string %}
  {%- set salt_call_args = "" %}
  {%- set systemd_unit_name = "salt-minion" %}

  # We don't check salt version in grains as in salt-ssh it equals version of salt-ssh, and we need to know installed package version
  {%- set installed_ver = salt["cmd.shell"]("dpkg -s salt-minion 2>/dev/null | grep Version | sed -e 's/^Version: //' -e 's/\..*$//' | grep " + salt_minion_version) %}
  # Also check if salt-minion is upgradable
  {%- set minion_upgradable = salt["cmd.shell"]("apt-get upgrade --dry-run 2>/dev/null | grep 'Inst salt-minion' | sed -e 's/ .*//'") %}
  {%- if salt_minion_version|string != installed_ver|string or minion_upgradable == "Inst" %}
salt_minion_update_restart:
  cmd.run:
    - name: |
        exec 0>&- # close stdin
        exec 1>&- # close stdout
        exec 2>&- # close stderr
        nohup /bin/sh -c 'apt-get update; apt-get -qy -o "DPkg::Options::=--force-confold" -o "DPkg::Options::=--force-confdef" install --allow-downgrades salt-common={{ salt_minion_version }}* salt-minion={{ salt_minion_version }}* && salt-call {{ salt_call_args }} --local service.restart {{ systemd_unit_name }}' &
  {%- endif %}

salt_minion_config_restart:
  cmd.run:
    - name: |
        exec 0>&- # close stdin
        exec 1>&- # close stdout
        exec 2>&- # close stderr
        nohup /bin/sh -c 'salt-call {{ salt_call_args }} --local service.restart {{ systemd_unit_name }}' &
    - onchanges:
        - file: {{ install_root }}/etc/salt/minion
        - file: {{ install_root }}/etc/salt/grains
        - file: {{ install_root }}/etc/salt/minion_id
        - file: {{ install_root }}/etc/salt/pki/minion/minion.pem
        - file: {{ install_root }}/etc/salt/pki/minion/minion.pub
        - file: {{ install_root }}/etc/salt/pki/minion/master_sign.pub
  {%- if "minion_master" in pillar["salt"]["minion"]["pki"] %}
        - file: {{ install_root }}/etc/salt/pki/minion/minion_master.pub
  {%- endif %}

{% else %}
salt_minion_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured or wrong OS, so nothing has been done. But it is OK.

{% endif %}
