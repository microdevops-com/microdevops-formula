# To clean up previous install:
#  - gitlab-ctl stop
#  - apt-get purge 'gitlab-*'
#  - rm -rf /etc/gitlab /opt/gitlab /var/opt/gitlab /run/gitlab /var/log/gitlab
#  - reboot
#
# Requirements:
# - You need to set up acme.sh beforehand, see sysadmws-formula/acme.
# - GitLab in LXD requires permissions as defined in docker profile.
#
# Here are the steps needed to connect google auth: https://docs.gitlab.com/ee/integration/google.html

{% if pillar["gitlab"] is defined %}
gitlab_repo:
  pkgrepo.managed:
    - humanname: Gitlab Repository
    - name: deb https://packages.gitlab.com/gitlab/gitlab-{{ pillar["gitlab"]["distribution"] }}/{{ grains["os"]|lower }}/ {{ grains["oscodename"] }} main
    - file: /etc/apt/sources.list.d/gitlab.list
    - key_url: https://packages.gitlab.com/gitlab/gitlab-{{ pillar["gitlab"]["distribution"] }}/gpgkey

gitlab_acme_run:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["gitlab"]["acme_account"] }}/verify_and_issue.sh gitlab {{ pillar["gitlab"]["domain"] }}"

gitlab_env:
  environ.setenv:
    - name: _
    - value:
        EXTERNAL_URL: "https://{{ pillar["gitlab"]["domain"] }}"
        GITLAB_ROOT_PASSWORD: {{ pillar["gitlab"]["root_password"] }}

gitlab_dirs:
  file.directory:
    - makedirs: True
    - names:
      - /var/lib/gitlab_docker_registry
      - /var/lib/gitlab_artifacts
      - /var/backups/gitlab_backups
      - /var/backups/gitlab_backups
      - /etc/gitlab
      - /etc/gitlab/nginx/conf.d

  {%- if "redirect" in pillar["gitlab"] %}
gitlab_redirect_acme_run:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["gitlab"]["redirect"]["acme_account"] }}/verify_and_issue.sh gitlab {{ pillar["gitlab"]["redirect"]["domain"] }}"

gitlab_nginx_redirect:
  file.managed:
    - name: etc/gitlab/nginx/conf.d/redirect.conf
    - contents: |
        server {
          listen 80;
          listen 443 ssl;
          server_name {{ pillar["gitlab"]["redirect"]["domain"] }};
          ssl_certificate /opt/acme/cert/gitlab_{{ pillar["gitlab"]["redirect"]["domain"] }}_fullchain.cer;
          ssl_certificate_key /opt/acme/cert/gitlab_{{ pillar["gitlab"]["redirect"]["domain"] }}_key.key;
          return 301 https://{{ pillar["gitlab"]["domain"] }}$request_uri;
        }
    - require:
      - cmd: gitlab_redirect_acme_run

  {%- endif %}

gitlab_config:
  file.managed:
    - name: /etc/gitlab/gitlab.rb
    - contents: |
        external_url 'https://{{ pillar["gitlab"]["domain"] }}'
        nginx['redirect_http_to_https'] = true
        nginx['ssl_certificate'] = "/opt/acme/cert/gitlab_{{ pillar["gitlab"]["domain"] }}_fullchain.cer"
        nginx['ssl_certificate_key'] = "/opt/acme/cert/gitlab_{{ pillar["gitlab"]["domain"] }}_key.key"
        nginx['custom_nginx_config'] = "include /etc/gitlab/nginx/conf.d/*.conf;"
        postgresql['listen_address'] = '*'
        postgresql['port'] = 5432
        postgresql['md5_auth_cidr_addresses'] = %w({{ pillar["gitlab"]["postgresql"]["md5_auth_cidr_addresses"] }})
        postgresql['trust_auth_cidr_addresses'] = %w(127.0.0.1/24 ::1/128)
        postgresql['sql_user'] = "gitlab"
        postgresql['sql_user_password'] = Digest::MD5.hexdigest "{{ pillar["gitlab"]["postgresql"]["sql_user_password"] }}" << postgresql['sql_user']
        gitlab_rails['db_host'] = '/var/opt/gitlab/postgresql/'
        gitlab_rails['omniauth_enabled'] = true
        gitlab_rails['omniauth_allow_single_sign_on'] = ['google_oauth2']
        gitlab_rails['omniauth_block_auto_created_users'] = true
        gitlab_rails['omniauth_providers'] = [
          { 
            "name" => "google_oauth2",
            "app_id" => "{{ pillar['gitlab']['google_oauth2']['app_id'] }}",
            "app_secret" => "{{ pillar['gitlab']['google_oauth2']['app_secret'] }}",
            "args" => { "access_type" => "offline", "approval_prompt" => '' }
          }
        ]
        gitlab_rails['smtp_enable'] = true
        gitlab_rails['smtp_address'] = "{{ pillar['gitlab']['smtp']['address'] }}"
        gitlab_rails['smtp_port'] = {{ pillar['gitlab']['smtp']['port'] }}
        gitlab_rails['smtp_user_name'] = "{{ pillar['gitlab']['smtp']['user_name'] }}"
        gitlab_rails['smtp_password'] = "{{ pillar['gitlab']['smtp']['password'] }}"
        gitlab_rails['smtp_domain'] = "{{ pillar['gitlab']['smtp']['domain'] }}"
        gitlab_rails['smtp_authentication'] = "login"
        gitlab_rails['smtp_enable_starttls_auto'] = true
        gitlab_rails['smtp_tls'] = false
        gitlab_rails['smtp_openssl_verify_mode'] = 'peer'
        gitlab_rails['incoming_email_enabled'] = true
        gitlab_rails['incoming_email_address'] = "{{ pillar['gitlab']['incoming_email']['address'] }}"
        gitlab_rails['incoming_email_email'] = "{{ pillar['gitlab']['incoming_email']['email'] }}"
        gitlab_rails['incoming_email_password'] = "{{ pillar['gitlab']['incoming_email']['password'] }}"
        gitlab_rails['incoming_email_host'] = "{{ pillar['gitlab']['incoming_email']['host'] }}"
        gitlab_rails['incoming_email_port'] = {{ pillar['gitlab']['incoming_email']['port'] }}
        gitlab_rails['incoming_email_ssl'] = true
        gitlab_rails['incoming_email_start_tls'] = false
        gitlab_rails['incoming_email_mailbox_name'] = "{{ pillar['gitlab']['incoming_email']['mailbox_name'] }}"
        gitlab_rails['incoming_email_idle_timeout'] = 60
        registry['enable'] = true
        registry_external_url 'https://{{ pillar["gitlab"]["domain"] }}:5001'
        registry['registry_http_addr'] = "localhost:5000"
        registry_nginx['ssl_certificate'] = "/opt/acme/cert/gitlab_{{ pillar["gitlab"]["domain"] }}_fullchain.cer"
        registry_nginx['ssl_certificate_key'] = "/opt/acme/cert/gitlab_{{ pillar["gitlab"]["domain"] }}_key.key"
        gitlab_rails['registry_path'] = "/var/lib/gitlab_docker_registry"
        gitlab_rails['artifacts_enabled'] = true
        gitlab_rails['artifacts_path'] = "/var/lib/gitlab_artifacts"
        gitlab_rails['backup_path'] = '/var/backups/gitlab_backups'
        gitlab_rails['pipeline_schedule_worker_cron'] = "*/10 * * * *"
        gitaly['ruby_num_workers'] = {{ pillar["gitlab"]["gitaly_ruby_num_workers"] }}

# Fix the issue when doing clean install with EXTERNAL_URL set - it will wait indefinately for service to start
gitlab_fix_clean_install_with_ext_url:
  cmd.run:
    - name: |
        timeout 180s bash -c 'until dpkg-query -s gitlab-{{ pillar["gitlab"]["distribution"] }} | grep -q "Status: install ok installed"; do systemctl start gitlab-runsvdir.service; sleep 10; done'
    - bg: True

gitlab_pkg:
  {%- if pillar["gitlab"]["version"] == "latest" %}
  pkg.latest:
    - refresh: True
    - pkgs:
      - gitlab-{{ pillar["gitlab"]["distribution"] }}
    - require:
      - cmd: gitlab_acme_run
  {%- else %}
  pkg.installed:
    - refresh: True
    - pkgs:
      - gitlab-{{ pillar["gitlab"]["distribution"] }}: '{{ pillar["gitlab"]["version"] }}*'
    - require:
      - cmd: gitlab_acme_run
  {%- endif %}

gitlab_reconfigure:
  cmd.run:
    - name: gitlab-ctl reconfigure
    - onchanges:
      - file: /etc/gitlab/gitlab.rb
    - require:
      - cmd: gitlab_acme_run
      - pkg: gitlab_pkg

gitlab_cron_gitlab_backup:
  cron.present:
    - identifier: gitlab_backup
    - user: root
    - minute: 10
    - hour: 5
    - name: "{{ pillar["gitlab"]["cron"]["backup_cmd"] }}"

gitlab_cron_registry_garbage_collect:
  cron.present:
    - identifier: gitlab_registry_garbage_collect
    - user: root
    - minute: 20
    - hour: 1
    - name: "{{ pillar["gitlab"]["cron"]["registry_garbage_collect_cmd"] }}"

gitlab_cron_clean_job_artifacts:
  cron.present:
    - identifier: gitlab_clean_job_artifacts
    - user: root
    - minute: 30
    - hour: 16
    - name: "{{ pillar["gitlab"]["cron"]["clean_job_artifacts_cmd"] }}"

# Fast lookup of authorized SSH keys in the database
# https://docs.gitlab.com/ee/administration/operations/fast_ssh_key_lookup.html
gitlab_ssh_git_config:
  file.managed:
    - name: /etc/ssh/sshd_config.d/gitlab.conf
    - contents: |
        Match User git
          AuthorizedKeysCommand /opt/gitlab/embedded/service/gitlab-shell/bin/gitlab-shell-authorized-keys-check git %u %k
          AuthorizedKeysCommandUser git
        Match all

gitlab_ssh_git_apply:
  cmd.run:
    - name: systemctl reload ssh.service
    - onchanges:
      - file: /etc/ssh/sshd_config.d/gitlab.conf

{% endif %}
