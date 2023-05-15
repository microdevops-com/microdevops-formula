{% if pillar['proftpd'] is defined and pillar['proftpd'] is not none %}

install_proftpd:
  pkg.installed:
    - allow_updates: True
    - refresh: True
    - pkgs:
      - proftpd-basic

ensure_proftpd_config_dir_exists:
  file.directory:
    - name: /etc/proftpd
    - user: root
    - group: root
    - dir_mode: 0755
    - require:
      - pkg: install_proftpd

ensure_proftpd_ftpd-users_file_exists:
  file.managed:
    - name: /etc/proftpd/ftpd.users
    - user: proftpd
    - group: root
    - mode: 0600
    - require:
      - pkg: install_proftpd
      - file: ensure_proftpd_config_dir_exists

ensure_proftpd_key_dir_exists:
  file.directory:
    - name: /etc/proftpd/keys
    - user: proftpd
    - group: root
    - dir_mode: 0750
    - require:
      - pkg: install_proftpd
      - file: ensure_proftpd_config_dir_exists

create_rsa_key:
  cmd.run:
    - name: ssh-keygen -m PEM -f proftpd_host_rsa_key -N '' -t rsa -b 4096
    - cwd: /etc/proftpd/keys
    - shell: /bin/bash
    - runas: proftpd
    - umask: 0377
    - creates: /etc/proftpd/keys/proftpd_host_rsa_key
    - require:
      - file: ensure_proftpd_key_dir_exists

create_dsa_key:
  cmd.run:
    - name: ssh-keygen -m PEM -f proftpd_host_dsa_key -N '' -t dsa -b 1024
    - cwd: /etc/proftpd/keys
    - shell: /bin/bash
    - runas: proftpd
    - umask: 0377
    - creates: /etc/proftpd/keys/proftpd_host_dsa_key
    - require:
      - file: ensure_proftpd_key_dir_exists

create_ecdsa_key:
  cmd.run:
    - name: ssh-keygen -m PEM -f proftpd_host_ecdsa_key -N '' -t ecdsa -b 521
    - cwd: /etc/proftpd/keys
    - shell: /bin/bash
    - runas: proftpd
    - umask: 0377
    - creates: /etc/proftpd/keys/proftpd_host_ecdsa_key
    - require:
      - file: ensure_proftpd_key_dir_exists

create_config_file:
  file.managed:
    - name: /etc/proftpd/conf.d/01-main.conf
    - user: proftpd
    - group: root
    - contents: | 
        DefaultRoot ~
        RequireValidShell off
        Port 21
        AuthUserFile /etc/proftpd/ftpd.users
        AuthOrder mod_auth_file.c
        PassivePorts 65000 65534
        LoadModule mod_sftp.c
        <IfModule mod_sftp.c>
          <VirtualHost 0.0.0.0>
                SFTPEngine on
                RequireValidShell off
                AllowOverwrite on
                Port 2226
                SFTPLog     /var/log/proftpd/sftp.log
                SFTPHostKey /etc/proftpd/keys/proftpd_host_rsa_key
                SFTPHostKey /etc/proftpd/keys/proftpd_host_dsa_key
                SFTPHostKey /etc/proftpd/keys/proftpd_host_ecdsa_key
                SFTPAuthMethods password
                SFTPOptions IgnoreSCPUploadPerms IgnoreSFTPUploadPerms IgnoreSFTPSetOwners IgnoreSFTPSetPerms IgnoreSFTPSetTimes
                AuthUserFile /etc/proftpd/ftpd.users
                DefaultRoot ~
          </VirtualHost>
        </IfModule>
    - require:
      - file: ensure_proftpd_key_dir_exists

proftpd_restart_trigger:
  test.succeed_with_changes:
    - require:
      - pkg: install_proftpd

ensure_proftpd_is_restarted:
  service.running:
    - name: proftpd
    - enable: True
    - full_restart: True
    - watch:
      - test: proftpd_restart_trigger
    - require:
      - pkg: install_proftpd

{% endif %}
