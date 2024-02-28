{#
This file acts as middleware, whose main role is
  - to create a symlinks for the config files
  - to issue (or don't) the certificate
  - to define the new ssl (dict) variable
  - to render the nginx config file (via _vhost.sls)
#}

# we either in the main conf section or in the redirects section
{%- if redirect is not defined %}
  {%- set acme_account = app["nginx"].get("ssl",{}).get("acme_account", none) %}
  {%- set domain = app["nginx"]["domain"] %}
  {%- set filename = app_name ~ ".conf" %}
{%- else %}
  {%- set acme_account = redirect.get("ssl",{}).get("acme_account", none) %}
  {%- set domain = redirect["domain"] %}
  {%- set filename = app_name ~ "_redirect_" ~ loop2_index ~ ".conf" %}
{%- endif %}

# create symlink for the currently processing config file
{%- if app["nginx"].get("link_sites-enabled", false) %}
app_{{ app_type }}_nginx_link_sites_enabled_{{ loop_index }}_{{ loop2_index }}:
  file.symlink:
    - name: {{ _nginx_sites_enabled_dir }}/{{ filename }}
    - target: {{ _nginx_sites_available_dir }}/{{ filename }}
{%- endif %}

# in the case of custom ssl or absence of ssl
{%- if acme_account is none %}
  {%- set ssl = app["nginx"].get("ssl",{}) %}
  {%- include "app/_nginx/_vhost.sls" with context %}

# in the case of acme and dns
{%- elif not "webroot" in acme_account %}

app_{{ app_type }}_acme_run_{{ loop_index }}_{{ loop2_index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ acme_account }}/verify_and_issue.sh {{ app_name }} {{ domain }}"
  {%- set ssl = {"cert":"/opt/acme/cert/" ~ app_name ~ "_" ~ domain.split()[0] ~ "_fullchain.cer","key":"/opt/acme/cert/" ~ app_name ~ "_" ~ domain.split()[0] ~ "_key.key"} %}
  {%- include "app/_nginx/_vhost.sls" with context %}

# in the case of acme and webroot
{%- else %}

    {%- set id = 1 %}
    {%- set ssl = {"cert":"/etc/ssl/certs/ssl-cert-snakeoil.pem","key":"/etc/ssl/private/ssl-cert-snakeoil.key"} %}
    {%- include "app/_nginx/_vhost.sls" with context %}
    {%- if pillar.get("nginx_reload", false) or app["nginx"].get("reload",false) %}
app_{{ app_type }}_nginx_reload_{{ loop_index }}_{{ loop2_index }}_{{ id }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/usr/sbin/nginx -t && /usr/sbin/nginx -s reload"
app_{{ app_type }}_acme_run_{{ loop_index }}_{{ loop2_index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ acme_account }}/verify_and_issue.sh {{ app_name }} {{ domain }}"
    {%- set id = 2 %}
    {%- set ssl = {"cert":"/opt/acme/cert/" ~ app_name ~ "_" ~ domain.split()[0] ~ "_fullchain.cer","key":"/opt/acme/cert/" ~ app_name ~ "_" ~ domain.split()[0] ~ "_key.key"} %}
    {%- include "app/_nginx/_vhost.sls" with context %}
app_{{ app_type }}_nginx_reload_{{ loop_index }}_{{ loop2_index }}_{{ id }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/usr/sbin/nginx -t && /usr/sbin/nginx -s reload"
    {%- endif %}

{%- endif %}
