# https://www.softether.org/4-docs/1-manual/6._Command_Line_Management_Utility_Manual/6.2_General_Usage_of_vpncmd
# https://www.softether.org/4-docs/1-manual/6._Command_Line_Management_Utility_Manual/6.3_VPN_Server_%2F%2F_VPN_Bridge_Management_Command_Reference_(For_Entire_Server)
# https://www.softether.org/4-docs/1-manual/6._Command_Line_Management_Utility_Manual/6.4_VPN_Server_%2F%2F_VPN_Bridge_Management_Command_Reference_(For_Virtual_Hub)
# https://github.com/SoftEtherVPN/SoftEtherVPN/issues/290
{% if (pillar['softether'] is defined) and (pillar['softether'] is not none) %}
  {%- if (pillar['softether']['vpnserver'] is defined) and (pillar['softether']['vpnserver'] is not none) %}
    {%- if (pillar['softether']['vpnserver']['install'] is defined) and (pillar['softether']['vpnserver']['install'] is not none) and (pillar['softether']['vpnserver']['install']) %}
      {%- if (pillar['softether']['vpnserver']['hubs'] is defined) and (pillar['softether']['vpnserver']['hubs'] is not none) %}
        {%- for hub in pillar['softether']['vpnserver']['hubs'] %}
          {%- if (pillar['softether']['vpnserver']['hubs'][hub]['delete'] is defined) and (pillar['softether']['vpnserver']['hubs'][hub]['delete'] is not none) and (pillar['softether']['vpnserver']['hubs'][hub]['delete']) %}
softether_vpnserver_delete_hub_{{ loop.index }}:
  cmd.run:
    - name: 'vpncmd localhost:443 /PASSWORD:"{{ pillar['softether']['vpnserver']['password'] }}" /SERVER /CMD HubList | grep -q "Virtual Hub Name.*|{{ hub }}$" && vpncmd localhost:443 /PASSWORD:"{{ pillar['softether']['vpnserver']['password'] }}" /SERVER /CMD HubDelete {{ hub }} || /bin/true'

          {%- else %}
softether_vpnserver_create_hub_{{ loop.index }}:
  cmd.run:
    - name: 'vpncmd localhost:443 /PASSWORD:"{{ pillar['softether']['vpnserver']['password'] }}" /SERVER /CMD HubList | grep -q "Virtual Hub Name.*|{{ hub }}$" || vpncmd localhost:443 /PASSWORD:"{{ pillar['softether']['vpnserver']['password'] }}" /SERVER /CMD HubCreate {{ hub }} /Password "{{ pillar['softether']['vpnserver']['hubs'][hub]['password'] }}"'

# Update password even of created with
softether_vpnserver_hub_password_{{ loop.index }}:
  cmd.run:
    - name: 'vpncmd localhost:443 /PASSWORD:"{{ pillar['softether']['vpnserver']['password'] }}" /SERVER /ADMINHUB:{{ hub }} /CMD SetHubPassword "{{ pillar['softether']['vpnserver']['hubs'][hub]['password'] }}"'

          {%- endif %}
          {%- if (pillar['softether']['vpnserver']['hubs'][hub]['cmds'] is defined) and (pillar['softether']['vpnserver']['hubs'][hub]['cmds'] is not none) %}
            {%- set h_loop = loop %}
            {%- for hub_cmd in pillar['softether']['vpnserver']['hubs'][hub]['cmds'] %}
softether_vpnserver_hub_cmd_{{ h_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: 'vpncmd localhost:443 /PASSWORD:"{{ pillar['softether']['vpnserver']['password'] }}" /SERVER /ADMINHUB:{{ hub }} /CMD {{ hub_cmd }}'

            {%- endfor %}
          {%- endif %}
          {%- if (pillar['softether']['vpnserver']['hubs'][hub]['users'] is defined) and (pillar['softether']['vpnserver']['hubs'][hub]['users'] is not none) %}
            {%- set h_loop = loop %}
            {%- for user in pillar['softether']['vpnserver']['hubs'][hub]['users'] %}
              {%- if (pillar['softether']['vpnserver']['hubs'][hub]['users'][user]['delete'] is defined) and (pillar['softether']['vpnserver']['hubs'][hub]['users'][user]['delete'] is not none) and (pillar['softether']['vpnserver']['hubs'][hub]['users'][user]['delete']) %}
softether_vpnserver_hub_delete_user_{{ h_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: 'vpncmd localhost:443 /PASSWORD:"{{ pillar['softether']['vpnserver']['password'] }}" /SERVER /ADMINHUB:{{ hub }} /CMD UserList | grep -q "User Name.*|{{ user }}$" && vpncmd localhost:443 /PASSWORD:"{{ pillar['softether']['vpnserver']['password'] }}" /SERVER /ADMINHUB:{{ hub }} /CMD UserDelete {{ user }} || /bin/true'

              {%- else %}
softether_vpnserver_hub_create_user_{{ h_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: 'vpncmd localhost:443 /PASSWORD:"{{ pillar['softether']['vpnserver']['password'] }}" /SERVER /ADMINHUB:{{ hub }} /CMD UserList | grep -q "User Name.*|{{ user }}$" || vpncmd localhost:443 /PASSWORD:"{{ pillar['softether']['vpnserver']['password'] }}" /SERVER /ADMINHUB:{{ hub }} /CMD UserCreate {{ user }} /GROUP:none /REALNAME:"{{ pillar['softether']['vpnserver']['hubs'][hub]['users'][user]['realname'] }}" /NOTE:none'

softether_vpnserver_hub_user_password_{{ h_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: 'vpncmd localhost:443 /PASSWORD:"{{ pillar['softether']['vpnserver']['password'] }}" /SERVER /ADMINHUB:{{ hub }} /CMD UserPasswordSet {{ user }} /PASSWORD:"{{ pillar['softether']['vpnserver']['hubs'][hub]['users'][user]['password'] }}"'

              {%- endif %}
            {%- endfor %}
          {%- endif %}
        {%- endfor %}
      {%- endif %}
      {%- if (pillar['softether']['vpnserver']['cmds'] is defined) and (pillar['softether']['vpnserver']['cmds'] is not none) %}
        {%- for cmd in pillar['softether']['vpnserver']['cmds'] %}
softether_vpnserver_cmd_{{ loop.index }}:
  cmd.run:
    - name: 'vpncmd localhost:443 /PASSWORD:"{{ pillar['softether']['vpnserver']['password'] }}" /SERVER /CMD {{ cmd }}'

        {%- endfor %}
      {%- endif %}
      {%- if
             (pillar['softether']['vpnserver']['server_key'] is defined) and (pillar['softether']['vpnserver']['server_key'] is not none) and
             (pillar['softether']['vpnserver']['server_cert'] is defined) and (pillar['softether']['vpnserver']['server_cert'] is not none)
      %}
softether_vpnserver_cert_key:
  file.managed:
    - name: '/opt/softether/vpnserver/server_key'
    - user: root
    - group: root
    - contents: {{ pillar['softether']['vpnserver']['server_key'] | yaml_encode }}

softether_vpnserver_cert_cert:
  file.managed:
    - name: '/opt/softether/vpnserver/server_cert'
    - user: root
    - group: root
    - contents: {{ pillar['softether']['vpnserver']['server_cert'] | yaml_encode }}

softether_vpnserver_cmd_cert_set:
  cmd.run:
    - name: 'vpncmd localhost:443 /PASSWORD:"{{ pillar['softether']['vpnserver']['password'] }}" /SERVER /CMD ServerCertSet /LOADCERT:"/opt/softether/vpnserver/server_cert" /LOADKEY:"/opt/softether/vpnserver/server_key"'
      {%- endif %}
    {%- endif %}
  {%- endif %}
{% endif %}
