{% if pillar["auditd"] is defined and pillar["auditd"] is not none %}
  {%- if grains["os_family"] != "Debian" or grains["osarch"] != "amd64" %}
auditd_unsupported_os:
  test.show_notification:
    - text: auditd state supports only Debian and Ubuntu on amd64, skipped
  {%- elif grains.get("virtual", "") | lower in ["container", "lxc", "lxd", "docker", "systemd-nspawn", "openvzve"] %}
auditd_container_unsupported:
  test.show_notification:
    - text: auditd needs the host kernel audit subsystem and does not work in a container, skipped
  {%- else %}
    {%- set auditd = pillar["auditd"] %}
    {%- set laurel = auditd.get("laurel", {}) %}
    {%- set laurel_version = laurel.get("version", "0.8.2") %}
    {%- set laurel_hash = laurel.get("source_hash", "sha256=c9b495acf67e9941760b24308145b513b2ee2a0a5bfe0a5bd70d5133c27c6e6c") %}
    {%- set laurel_name = "laurel-" ~ laurel_version ~ "-x86_64-glibc" %}
    {%- set laurel_source = laurel.get("source", "https://github.com/threathunters-io/laurel/releases/download/v" ~ laurel_version ~ "/" ~ laurel_name ~ ".tar.gz") %}
    {#- auditd 2 (focal, bullseye and older) keeps plugins in audisp, auditd 3 in audit #}
    {%- if grains["oscodename"] in ["bionic", "focal", "buster", "bullseye"] %}
      {%- set plugins_dir = "/etc/audisp/plugins.d" %}
    {%- else %}
      {%- set plugins_dir = "/etc/audit/plugins.d" %}
    {%- endif %}

auditd_pkg:
  pkg.installed:
    - pkgs:
      - auditd
      - acl

auditd_laurel_user:
  user.present:
    - name: _laurel
    - system: True
    - home: /var/log/laurel
    - createhome: False
    - shell: /usr/sbin/nologin

auditd_laurel_log_dir:
  file.directory:
    - name: /var/log/laurel
    - user: _laurel
    - group: _laurel
    - mode: 750
    - require:
      - user: auditd_laurel_user

auditd_laurel_archive:
  archive.extracted:
    - name: /opt/laurel/{{ laurel_version }}
    - source: {{ laurel_source }}
    - source_hash: {{ laurel_hash }}
    - options: --strip-components=1
    - enforce_toplevel: False
    - if_missing: /opt/laurel/{{ laurel_version }}/bin/laurel

auditd_laurel_binary:
  cmd.run:
    - name: install -m 755 -o root -g root /opt/laurel/{{ laurel_version }}/bin/laurel /usr/local/sbin/laurel
    - unless: cmp -s /opt/laurel/{{ laurel_version }}/bin/laurel /usr/local/sbin/laurel
    - require:
      - archive: auditd_laurel_archive

auditd_laurel_config:
  file.managed:
    - name: /etc/laurel/config.toml
    - source: salt://auditd/files/laurel.config.toml
    - template: jinja
    - makedirs: True
    - mode: 644
    - user: root
    - group: root
    - defaults:
        log_size: {{ laurel.get("log_size", 50000000) }}
        log_generations: {{ laurel.get("log_generations", 5) }}

auditd_laurel_plugin:
  file.managed:
    - name: {{ plugins_dir }}/laurel.conf
    - source: salt://auditd/files/laurel.plugin.conf
    - makedirs: True
    - mode: 640
    - user: root
    - group: root
    - require:
      - pkg: auditd_pkg

auditd_rules:
  file.managed:
    - name: /etc/audit/rules.d/50-microdevops.rules
    - source: salt://auditd/files/microdevops.rules
    - template: jinja
    - mode: 640
    - user: root
    - group: root
    - require:
      - pkg: auditd_pkg

auditd_rules_finalize:
  file.managed:
    - name: /etc/audit/rules.d/99-finalize.rules
    - mode: 640
    - user: root
    - group: root
    - contents: |
        # Managed by Salt. Lock the rules until reboot, must stay the last rule.
        {%- if auditd.get("immutable", True) %}
        -e 2
        {%- else %}
        -e 1
        {%- endif %}
    - require:
      - pkg: auditd_pkg

auditd_service:
  service.running:
    - name: auditd
    - enable: True
    - require:
      - pkg: auditd_pkg

# systemctl restart auditd is refused by the unit (RefuseManualStop), the service command is the supported way.
# It reloads plugins. It does not touch rules locked with -e 2.
auditd_restart_for_plugin:
  cmd.run:
    - name: service auditd restart
    - onchanges:
      - cmd: auditd_laurel_binary
      - file: auditd_laurel_config
      - file: auditd_laurel_plugin
    - require:
      - service: auditd_service

# With -e 2 loaded rules cannot change until reboot: do not fail the state, say it clearly instead.
auditd_load_rules:
  cmd.run:
    - name: |
        if auditctl -s | grep -q '^enabled 2'; then
          echo "WARNING: audit rules are locked (enabled 2), the new rules apply after a reboot"
        else
          augenrules --load
        fi
    - onchanges:
      - file: auditd_rules
      - file: auditd_rules_finalize
    - require:
      - service: auditd_service
  {%- endif %}
{% endif %}
