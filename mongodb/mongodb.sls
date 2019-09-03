{% if pillar['mongodb'] is defined and pillar['mongodb'] is not none %}
  {%- for db in pillar['mongodb']['databases'] %}
    {%- set a_loop = loop %}
    {%- for user in db['users'] %}
      {%- set b_loop = loop %}
mongodb_user_present_{{ a_loop.index }}_{{ b_loop.index }}:
  mongodb_user.present:
    - name: {{ user['name'] }}
    - passwd: {{ user['password'] }}
    - database: {{ db['name'] }}
    - user: {{ pillar['mongodb']['admin']['user'] }}
    - password: {{ pillar['mongodb']['admin']['password'] }}
    - host: {{ pillar['mongodb']['admin']['host'] }}
    - port: {{ pillar['mongodb']['admin']['port'] }}
    - authdb: {{ pillar['mongodb']['admin']['authdb'] }}
    - roles: {{ user['roles'] }}
    {%- endfor %}
  {%- endfor %}
{% endif %}
