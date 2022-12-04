{%- if  pillar["sentry"] is defined and "catch_root_email" in pillar["sentry"] and pillar["sentry"]["catch_root_email"]["enabled"] %}
  {%- if not salt["file.file_exists"]("/usr/local/bin/sentry-cli") %}
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
        defaults.url={{ pillar["sentry"]["catch_root_email"]["SENTRY_URL"] }}
        auth.dsn={{ pillar["sentry"]["catch_root_email"]["SENTRY_DSN"] }}
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

  {%- if "newaliases" in pillar["sentry"]["catch_root_email"] and pillar["sentry"]["catch_root_email"]["newaliases"] %}
set_alias:
  alias.present:
    - name: root
    - target: "| /opt/sysadmws/sentry_catch_root_mail/sentry-sender.sh"

    {%- if pillar["sentry"]["catch_root_email"]["catch_other_users_email"] and salt["file.file_exists"]("/opt/sysadmws/sentry_catch_root_mail/set-alias-for-all-users.sh")%}
set_alias_for_all_users:
  cmd.run:
    - name: /opt/sysadmws/sentry_catch_root_mail/set-alias-for-all-users.sh
    - shell: /bin/bash
cron_for_set-alias-for-all-users.sh:
  cron.present:
    - identifier: sentry catch mail for all users
    - name: /opt/sysadmws/sentry_catch_root_mail/set-alias-for-all-users.sh
    - user: root
    - minute: 0
    - hour: 0
    {%- endif %}

reload_aliases:
  cmd.run:
    - name: newaliases

  {%- endif %}
{%- endif %}
