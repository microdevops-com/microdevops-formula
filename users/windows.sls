{% if (pillar['windows_users'] is defined) and (pillar['windows_users'] is not none) %}
windows_ps_scripts_admin_users_process:
  file.managed:
    - name: 'C:\Windows\System32\admin_users_process.ps1'
    - source: salt://users/windows_ps_scripts/admin_users_process.ps1

windows_ps_scripts_execution_policy_unrestrict:
  cmd.run:
    - name: powershell.exe Set-ExecutionPolicy -Force Unrestricted

  {%- for windows_user, user_params in pillar['windows_users'].items() %}
windows_admins_{{ loop.index }}:
  user.present:
    - name: {{ windows_user }}
    - fullname: {{ user_params['fullname'] }}
    - remove_groups: {{ user_params['remove_groups'] }}
    - password: {{ user_params['password'] }}

    {%- if (user_params['is_admin'] is defined) and (user_params['is_admin'] is not none) and (user_params['is_admin']) %}
windows_admins_admin_users_process_{{ loop.index }}:
  cmd.run:
    - name: 'powershell.exe C:\Windows\system32\admin_users_process.ps1 {{ windows_user }}'
    {%- endif %}
  {%- endfor %}

  {%- if not ((pillar['windows_unrestricted'] is defined) and (pillar['windows_unrestricted'] is not none) and (pillar['windows_unrestricted'])) %}
# This should be in the end of file
windows_ps_scripts_execution_policy_restrict:
  cmd.run:
    - name: powershell.exe Set-ExecutionPolicy -Force Restricted
  {%- endif %}
{% endif %}
