{%- if (pillar['proftpd'] is defined) and (pillar['proftpd'] is not none) %}
  {%- if (pillar['proftpd']['users'] is defined) and (pillar['proftpd']['users'] is not none) %}
    {%- for proftpd_user in pillar['proftpd']['users'] %}
      {%- if (pillar['proftpd']['users'][proftpd_user]['delete'] is defined) and (pillar['proftpd']['users'][proftpd_user]['delete'] is not none) and (pillar['proftpd']['users'][proftpd_user]['delete']) %}
proftpd_delete_user_{{ loop.index }}:
  cmd.run:
    - name: 'grep {{ proftpd_user }} /etc/proftpd/ftpd.users && ftpasswd --passwd --file=/etc/proftpd/ftpd.users --name={{ proftpd_user }} --delete-user || echo "user not exist"'
        {%- else %}
create_proftpd_user_{{ loop.index }}:
  cmd.run:
    - name: 'PROFTPD_PASS="{{ pillar['proftpd']['users'][proftpd_user]['password'] }}" && echo $PROFTPD_PASS | ftpasswd --stdin --passwd --file=/etc/proftpd/ftpd.users --name={{ proftpd_user }} --uid=$(id -u {{ pillar['proftpd']['users'][proftpd_user]['user'] }}) --gid=$(id -g {{ pillar['proftpd']['users'][proftpd_user]['group'] }}) --home=$(echo ~{{ pillar['proftpd']['users'][proftpd_user]['homedir'] }}) --shell=/bin/false'
    - runas: 'root'
      {%- endif %}
      {%- if (pillar['proftpd']['users'][proftpd_user]['makedir'] is defined) and (pillar['proftpd']['users'][proftpd_user]['makedir'] is not none) and (pillar['proftpd']['users'][proftpd_user]['makedir']) %}
create_proftpd_user_directory{{ loop.index }}:
  file.directory:
    - name: {{ pillar['proftpd']['users'][proftpd_user]['homedir'] }}
    - user: {{ pillar['proftpd']['users'][proftpd_user]['user'] }}
    - group: {{ pillar['proftpd']['users'][proftpd_user]['group'] }}
    - makedirs: True
      {%- endif %}
    {%- endfor %}
  {%- endif %}
{%- endif %}
