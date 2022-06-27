{%- if pillar['sentry']['catch_root_email']['enabled'] %}
  {%- if not salt['file.file_exists']('/usr/local/bin/sentry-cli') %}
install_sentry-cli:
  cmd.run:
    - name: "curl -sL https://sentry.io/get-cli/ | bash"
    - shell: /bin/bash
  {%- else %}
update_sentry-cli:
  cmd.run:
    - name: "/usr/local/bin/sentry-cli update"
    - shell: /bin/bash
  {%- endif %}

sentry_properties:
  file.managed:
    - name: "/opt/sysadmws/sentry_catch_root_mail/sentry.properties"
    - contents: |
        defaults.url={{ pillar['sentry']['catch_root_email']['SENTRY_URL'] }}
        auth.token={{ pillar['sentry']['catch_root_email']['SENTRY_AUTH_TOKEN'] }}
        auth.dsn={{ pillar['sentry']['catch_root_email']['SENTRY_DSN'] }}
    - makedirs: True

create_logfile:
  file.touch:
    - name: /opt/sysadmws/sentry_catch_root_mail/log/sentry-cli.log
    - makedirs: True

permissions:
  file.directory:
    - name: /opt/sysadmws/sentry_catch_root_mail/log
    - dir_mode: 775
    - file_mode: 666
    - follow_symlinks: True
    - recurse:
      - mode
{%- endif %}
