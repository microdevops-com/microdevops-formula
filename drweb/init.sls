{% if pillar["drweb"] is defined %}

cert:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["drweb"]["acme_account"] }}/verify_and_issue.sh drweb {{ pillar["drweb"]["servername"] }}"

drweb_install_00:
  pkgrepo.managed:
    - humanname: Dr.Web Repository
    - name: deb http://repo.drweb.com/drweb/debian 11.1 non-free
    - file: /etc/apt/sources.list.d/drweb.list
    - keyid: 8C42FC58D8752769
    - keyserver: keyserver.ubuntu.com
drweb_install_01:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs:
        #- drweb-mail-servers
        - drweb-maild
        - drweb-se
        - drweb-dws
        - drweb-antispam
        - drweb-vaderetro
        - drweb-httpd
        - drweb-openssl
        - drweb-netcheck

  {% if "license_key" in pillar["drweb"] %}
drweb_license_key_install:
  file.managed:
    - name: /etc/opt/drweb.com/drweb32.key
      source: 'salt://{{ pillar["drweb"]["license_key"] }}'
      user: root
      group: root
      mode: 0644
drweb_configuration_reload:
  cmd.run:
    - name: drweb-ctl reload
    - onchanges:
      - file: /etc/opt/drweb.com/drweb32.key
  {% endif %}

drweb_log_dir:
  file.directory:
    - name: /var/log/drweb
    - mode: 755
    - user: drweb
    - group: drweb

drweb_configure_00:
  cmd.run:
    - name: drweb-ctl cfset HTTPD.AdminListen {{ pillar["drweb"]["ip"] }}:443
drweb_configure_01:
  cmd.run:
    - name: drweb-ctl cfset HTTPD.AdminSslCertificate /opt/acme/cert/{{ pillar["drweb"]["servername"] }}/fullchain.cer
drweb_configure_02:
  cmd.run:
    - name: drweb-ctl cfset HTTPD.AdminSslKey /opt/acme/cert/{{ pillar["drweb"]["servername"] }}/{{ pillar["drweb"]["servername"] }}.key
drweb_configure_03:
  cmd.run:
    - name: drweb-ctl cfset ScanEngine.Log /var/log/drweb/scanning_engine.log
drweb_configure_04:
  cmd.run:
    - name: drweb-ctl cfset ScanEngine.LogLevel {{ pillar["drweb"]["ScanEngine_LogLevel"] }}
drweb_configure_05:
  cmd.run:
    - name: drweb-ctl cfset MailD.LogLevel {{ pillar["drweb"]["MailD_LogLevel"] }}
drweb_configure_06:
  cmd.run:
    - name: drweb-ctl cfset MailD.Log /var/log/drweb/maild.log
drweb_configure_07:
  cmd.run:
    - name: drweb-ctl cfset MailD.RepackPassword "HMAC({{ pillar["drweb"]["secret_word"] }})"
drweb_configure_08:
  cmd.run:
    - name: drweb-ctl cfset MailD.MilterDebugIpc {{ pillar["drweb"]["MailD_MilterDebugIpc"] }}
drweb_configure_09:
  cmd.run:
    - name: drweb-ctl cfset MailD.MilterTraceContent {{ pillar["drweb"]["MailD_MilterTraceContent"] }}
drweb_configure_10:
  cmd.run:
    - name: drweb-ctl cfset MailD.MilterSocket {{ pillar["drweb"]["ip"] }}:{{ pillar["drweb"]["smtp_milter_port"] }}
drweb_configure_11:
  cmd.run:
    - name: drweb-ctl cfset Antispam.LogLevel {{ pillar["drweb"]["Antispam_LogLevel"] }}
drweb_configure_12:
  cmd.run:
    - name: drweb-ctl cfset Antispam.Log /var/log/drweb/antispam.log

  {% if "MilterHook" in pillar["drweb"] %}
drweb_create_file_milter_hook_lua:
  file.managed:
    - name: /etc/opt/drweb.com/milter_hook.lua
      source: 'salt://{{ pillar["drweb"]["MilterHook"] }}'
      user: root
      group: root
      mode: 0644

    {% if "whitelist_send_to" in pillar["drweb"]["MilterHook"] %}
drweb_create_file_whitelist_send_to:
  file.managed:
    - name: /etc/opt/drweb.com/lists/whitemails_to.txt
      source: 'salt://{{ pillar["drweb"]["MilterHook"]["whitelist_send_to"] }}'
      user: root
      group: root
      mode: 0644
      makedirs: True
    {% endif %}
    {% if "whitelist_send_from" in pillar["drweb"]["MilterHook"] %}
drweb_create_file_whitelist_send_from_file:
  file.managed:
    - name: /etc/opt/drweb.com/lists/whitemails.txt
      source: 'salt://{{ pillar["drweb"]["MilterHook"]["whitelist_send_from"] }}'
      user: root
      group: root
      mode: 0644
      makedirs: True
    {% endif %}
    {% if "blacklist_send_from" in pillar["drweb"]["MilterHook"] %}
drweb_create_file_blacklist_send_from_file:
  file.managed:
    - name: /etc/opt/drweb.com/lists/blackmails.txt
      source: 'salt://{{ pillar["drweb"]["MilterHook"]["blacklist_send_from"] }}'
      user: root
      group: root
      mode: 0644
      makedirs: True
    {% endif %}

drweb_load_milter_hook_lua_file:
  cmd.run:
    - name: drweb-ctl cfset MailD.MilterHook /etc/opt/drweb.com/milter_hook.lua

  {% endif %}

{% endif %}
