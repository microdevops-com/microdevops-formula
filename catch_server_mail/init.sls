{%- if  pillar["catch_server_mail"] is defined and "sentry" in pillar["catch_server_mail"] %}
  {%- if "domain_override" in pillar["catch_server_mail"] -%}
    {%- do pillar["catch_server_mail"].update({"domain": pillar["catch_server_mail"]["domain_override"]]}) %}
  {%- endif -%}
  {%- if "org-slug_override" in pillar["catch_server_mail"] -%}
    {%- do pillar["catch_server_mail"].update({"org-slug": pillar["catch_server_mail"]["org-slug_override"]]}) %}
  {%- endif -%}
  {%- if "project-slug_override" in pillar["catch_server_mail"] -%}
    {%- do pillar["catch_server_mail"].update({"project-slug": pillar["catch_server_mail"]["project-slug_override"]]}) %}
  {%- endif -%}
  {%- if "auth_token_override" in pillar["catch_server_mail"] -%}
    {%- do pillar["catch_server_mail"].update({"auth_token": pillar["catch_server_mail"]["auth_token_override"]]}) %}
  {%- endif -%}
  {%- if "dsn_public_override" in pillar["catch_server_mail"] -%}
    {%- do pillar["catch_server_mail"].update({"dsn_public": pillar["catch_server_mail"]["dsn_public_override"]]}) %}
  {%- endif -%}
catch_server_mail_sentry-cli:
  cmd.run:
    - name: |
        curl -L "https://release-registry.services.sentry.io/apps/sentry-cli/latest?response=download&arch={{ grains["cpuarch"] }}&platform=Linux&package=sentry-cli" -o /usr/local/bin/sentry-cli
        chmod +x /usr/local/bin/sentry-cli

catch_server_mail_dir:
  file.directory:
    - name: /opt/microdevops/catch_server_mail
    - makedirs: True

# Catcher is run by different users, so log dir and file should be all writable
catch_server_mail_log_dir:
  file.directory:
    - name: /opt/microdevops/catch_server_mail/log
    - mode: 0777

catch_server_mail_sentry_log_touch:
  cmd.run:
    - name: |
        touch /opt/microdevops/catch_server_mail/log/sentry.log
        chmod 0666 /opt/microdevops/catch_server_mail/log/sentry.log

# We gradually add needed lines to file if they do not exist
catch_server_mail_sentry_properties_touch:
  file.touch:
    - name: /opt/microdevops/catch_server_mail/sentry.properties

catch_server_mail_sentry_properties_line_1:
  file.replace:
    - name: /opt/microdevops/catch_server_mail/sentry.properties
    - pattern: '^defaults.url=.*$'
    - repl: 'defaults.url=https://{{ pillar["catch_server_mail"]["sentry"]["domain"] }}/'
    - append_if_not_found: True
    - backup: False

catch_server_mail_sentry_properties_line_2:
  file.replace:
    - name: /opt/microdevops/catch_server_mail/sentry.properties
    - pattern: '^defaults.org=.*$'
    - repl: 'defaults.org={{ pillar["catch_server_mail"]["sentry"]["org-slug"] }}'
    - append_if_not_found: True
    - backup: False

catch_server_mail_sentry_properties_line_3:
  file.replace:
    - name: /opt/microdevops/catch_server_mail/sentry.properties
    - pattern: '^defaults.project=.*$'
    - repl: 'defaults.project={{ pillar["catch_server_mail"]["sentry"]["project-slug"] }}'
    - append_if_not_found: True
    - backup: False

catch_server_mail_sentry_properties_line_4:
  file.replace:
    - name: /opt/microdevops/catch_server_mail/sentry.properties
    - pattern: '^auth.token=.*$'
    - repl: 'auth.token={{ pillar["catch_server_mail"]["sentry"]["auth_token"] }}'
    - append_if_not_found: True
    - backup: False

# Sed inplace if line already exists, add line if not
catch_server_mail_sentry_properties_line_5:
  cmd.run:
    - shell: /bin/bash
    - name: |
        PROJECT_ID=$(SENTRY_PROPERTIES=/opt/microdevops/catch_server_mail/sentry.properties sentry-cli projects list | grep "| *{{ pillar["catch_server_mail"]["sentry"]["project-slug"] }} *|" | awk '{print $2}')
        # Check if PROJECT_ID is integer
        if [[ $PROJECT_ID =~ ^[0-9]+$ ]]; then
          if grep -q auth.dsn /opt/microdevops/catch_server_mail/sentry.properties; then
            sed -i "s#^auth.dsn=.*#auth.dsn=https://{{ pillar["catch_server_mail"]["sentry"]["dsn_public"] }}@{{ pillar["catch_server_mail"]["sentry"]["domain"] }}/${PROJECT_ID}#" /opt/microdevops/catch_server_mail/sentry.properties
          else
            echo "auth.dsn=https://{{ pillar["catch_server_mail"]["sentry"]["dsn_public"] }}@{{ pillar["catch_server_mail"]["sentry"]["domain"] }}/${PROJECT_ID}" >> /opt/microdevops/catch_server_mail/sentry.properties
          fi
        else
          echo "Project {{ pillar["catch_server_mail"]["sentry"]["project-slug"] }} not found"
          false
        fi

  # If all_users is True, set mail alias to sender for all users, otherwise set alias for root only
  {%- set users = ["root"] %}
  {%- if "all_users" in pillar["catch_server_mail"]["sentry"] and pillar["catch_server_mail"]["sentry"]["all_users"] %}
    # Read all users from /etc/passwd
    # Add users only if id is greater than 999
    {%- for user in salt["cmd.run"]("cut -d: -f1 /etc/passwd").split() %}
      {%- if salt["cmd.run"]("id -u " ~ user) | int > 999 and user != "nobody" %}
        {%- do users.append(user) %}
      {%- endif %}
    {%- endfor %}
  {%- endif %}

  {%- for user in users %}
catch_server_mail_set_alias_{{ user }}:
    # If enabled - set alias, if not - remove alias
    {%- if pillar["catch_server_mail"]["enabled"] %}
  alias.present:
    - name: {{ user }}
    - target: "| /opt/microdevops/catch_server_mail/sentry.sh"
    {%- else %}
  alias.absent:
    - name: {{ user }}
    {%- endif %}

  {%- endfor %}

catch_server_mail_reload_aliases:
  cmd.run:
    - name: newaliases

# Save environment, location, description to sentry.env
# This file is used by sentry.sh
catch_server_mail_sentry_env:
  file.managed:
    - name: /opt/microdevops/catch_server_mail/sentry.env
    - contents: |
        SERVER_ENVIRONMENT="{{ pillar["catch_server_mail"]["sentry"]["environment"]|default("infra") }}"
        SERVER_LOCATION="{{ pillar["catch_server_mail"]["sentry"]["location"]|default("") }}"
        SERVER_DESCRIPTION="{{ pillar["catch_server_mail"]["sentry"]["description"]|default("") }}"

{% else %}
catch_server_mail_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured, so nothing has been done. But it is OK.

{%- endif %}
