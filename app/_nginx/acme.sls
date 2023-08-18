{#
This file acts as middleware, whose main role is
 to issue (or don't) a certificate and define new ssl (dict) variable,
 which in turn will be used in _vhost.sls.
#}

{%- if redirect is not defined %}
  {%- set acme_account = app["nginx"]["ssl"].get("acme_account", none) %}
  {%- set domain = app["nginx"]["domain"] %}
  {%- set loop2_index = 0 %}
{%- else %}
  {%- set acme_account = redirect["ssl"].get("acme_account", none) %}
  {%- set domain = redirect["domain"] %}
{%- endif %}

{%- if acme_account is none %}
  {%- set ssl = app["nginx"].get("ssl",{}) %}
  {%- include "app/_nginx/_vhost.sls" with context %}
{%- elif not "webroot" in acme_account %}
app_{{ app_type }}_acme_run_{{ loop_index }}_{{ loop2_index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ acme_account }}/verify_and_issue.sh {{ app_name }} {{ domain }}"
  {%- set ssl = {"cert":"/opt/acme/cert/" ~ app_name ~ "_" ~ domain ~ "_fullchain.cer","key":"/opt/acme/cert/" ~ app_name ~ "_" ~ domain ~ "_key.key"} %}
  {%- include "app/_nginx/_vhost.sls" with context %}

  {%- else %}

  {%- if salt["cmd.retcode"]("/usr/sbin/nginx -t") == 0 %}
    {%- set ssl = {"cert":"/etc/ssl/certs/ssl-cert-snakeoil.pem","key":"/etc/ssl/private/ssl-cert-snakeoil.key"} %}
    {%- set id = 1 %}
    {%- include "app/_nginx/_vhost.sls" with context %}
app_{{ app_type }}_nginx_link_sites_enabled_{{ loop_index }}_{{ loop2_index }}:
  file.symlink:
    - name: {{ _nginx_sites_enabled_dir }}/{{ app_name }}.conf
    - target: {{ _nginx_sites_available_dir }}/{{ app_name }}.conf
app_{{ app_type }}_nginx_reload_{{ loop_index }}_{{ loop2_index }}_{{ id }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/usr/sbin/nginx -t && /usr/sbin/nginx -s reload"
app_{{ app_type }}_acme_run_{{ loop_index }}_{{ loop2_index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ acme_account }}/verify_and_issue.sh {{ app_name }} {{ domain }}"
     {%- set ssl = {"cert":"/opt/acme/cert/" ~ app_name ~ "_" ~ domain ~ "_fullchain.cer","key":"/opt/acme/cert/" ~ app_name ~ "_" ~ domain ~ "_key.key"} %}
     {%- set id = 2 %}
     {%- include "app/_nginx/_vhost.sls" with context %}
app_{{ app_type }}_nginx_reload_{{ loop_index }}_{{ loop2_index }}_{{ id }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/usr/sbin/nginx -t && /usr/sbin/nginx -s reload"
  {%- else %}
app_{{ app_type }}_nginx_configtest_{{ loop_index }}_{{ loop2_index }}:
  test.configurable_test_state:
    - name: state_warning
    - changes: False
    - result: False
    - comment: |
        WARNING: Initial nginx config test failed! Please fix those errors and try once more
  {%- endif %}
{%- endif %}
