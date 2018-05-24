{% if (pillar['windows_users'] is defined) and (pillar['windows_users'] is not none) %}
windows_scripts_admin_user:
  file.managed:
    - name: 'C:\Windows\System32\admin_user.ps1'
    - source: salt://users/scripts/admin_user.ps1

windows_execution_policy_unrestrict:
  cmd.run:
    - name: powershell.exe Set-ExecutionPolicy -Force Unrestricted

  {%- for windows_user, user_params in pillar['windows_users'].items() %}
windows_user_present_{{ loop.index }}:
  user.present:
    - name: {{ windows_user }}
    - fullname: {{ user_params['fullname'] }}
    - remove_groups: {{ user_params['remove_groups'] }}
    - password: {{ user_params['password'] }}
    {%- if (user_params['groups'] is defined) and (user_params['groups'] is not none) %}
    - groups: {{ user_params['groups'] }}
    {%- endif %}

    {%- if (user_params['password_never_expires'] is defined) and (user_params['password_never_expires'] is not none) and (user_params['password_never_expires']) %}
windows_user_password_never_expires_{{ loop.index }}:
  module.run:
    - name: user.update
    - m_name: {{ windows_user }}
    - password_never_expires: True
    {%- endif %}

    {%- if (user_params['admin'] is defined) and (user_params['admin'] is not none) and (user_params['admin']) %}
windows_user_admin_user_{{ loop.index }}:
  cmd.run:
    - name: 'powershell.exe C:\Windows\system32\admin_user.ps1 {{ windows_user }}'
    {%- endif %}
  {%- endfor %}

  {%- if not ((pillar['windows_unrestricted'] is defined) and (pillar['windows_unrestricted'] is not none) and (pillar['windows_unrestricted'])) %}
# This should be in the end of file
windows_execution_policy_restrict:
  cmd.run:
    - name: powershell.exe Set-ExecutionPolicy -Force Restricted
  {%- endif %}
{% endif %}
