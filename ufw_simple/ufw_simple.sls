{% if (pillar['ufw'] is defined) and (pillar['ufw'] is not none) %}
  {%- if (pillar['ufw']['enabled'] is defined) and (pillar['ufw']['enabled'] is not none) and (pillar['ufw']['enabled']) %}
ufw_update_deb:
  pkg.installed:
    - sources:
      - ufw: 'salt://ufw/files/ufw_0.35-4_all.deb'

    {%- if  (pillar['ufw']['nat_enabled'] is defined) and (pillar['ufw']['nat_enabled'] is not none) and (pillar['ufw']['nat_enabled']) %}
ufw_nat_file_1:
  file.managed:
    - name: '/etc/ufw/sysctl.conf'
    - source: 'salt://ufw/files/ufw_sysctl.conf'
    - mode: 0644

ufw_nat_file_2:
  file.managed:
    - name: '/etc/default/ufw'
    - source: 'salt://ufw/files/etc_default_ufw'
    - mode: 0644

ufw_restart:
  cmd.run:
    - name: 'ufw disable && sleep 5 && ufw enable'
    - runas: root
    - onchanges:
      - file: '/etc/ufw/sysctl.conf'
      - file: '/etc/default/ufw'
    {%- endif %}

    {%- if  (pillar['ufw']['logging'] is defined) and (pillar['ufw']['logging'] is not none) %}
ufw_set_logging:
  cmd.run:
    - name: {{ 'ufw logging ' ~ pillar['ufw']['logging'] }}
    - runas: root
    {%- endif %}

    {%- if  (pillar['ufw']['allow'] is defined) and (pillar['ufw']['allow'] is not none) %}
      {%- for item_name, item_params in pillar['ufw']['allow'].items() %}
        {%- if (item_params['from'] is defined) and (item_params['from'] is not none) %}
          {%- set item_from = item_params['from'] %}
        {%- else %}
          {%- set item_from = {'any': 'any'} %}
        {%- endif %}
        {%- if (item_params['to'] is defined) and (item_params['to'] is not none) %}
          {%- set item_to = item_params['to'] %}
        {%- else %}
          {%- set item_to = {'any': 'any'} %}
        {%- endif %}
        {%- set i_loop = loop %}
        {%- for i_from in item_from %}
          {%- set j_loop = loop %}
          {%- for i_to in item_to %}
ufw_allow_rule_{{ i_loop.index }}_{{ j_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: {{ 'ufw allow proto ' ~ item_params['proto'] ~ ' from ' ~ item_from[i_from] ~ ' to ' ~ item_to[i_to] ~ ' port ' ~ item_params['to_port'] ~ ' comment \'' ~ item_name ~ ' from ' ~ i_from ~ ' to ' ~ i_to ~ '\'' }}
    - runas: root
          {%- endfor %}
        {%- endfor %}
      {%- endfor %}
    {%- endif %}

ufw_enable:
  cmd.run:
    - name: 'ufw enable'
    - runas: root

  {%- endif %}
{% endif %}
