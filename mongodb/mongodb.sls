{% if pillar['mongodb'] is defined and pillar['mongodb'] is not none %}
  {%- if pillar['mongodb']['enabled'] is defined and pillar['mongodb']['enabled'] is not none and pillar['mongodb']['enabled'] %}
    {%- if pillar['mongodb']['version'] is defined and pillar['mongodb']['version'] is not none %}
install_1:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs: 
        - python-pip
install_2:
  pip.installed:
    - name: pymongo
    - reload_modules: True
install_3:
  pkg.removed:
    - pkgs: 
        - python-pymongo
        - python-pymongo-ext
install_4:
  pkgrepo.managed:
    - humanname: MongoDB Community Edition
    - name: deb [arch=amd64] https://repo.mongodb.org/apt/ubuntu {{ grains['oscodename'] }}/mongodb-org/{{ pillar['mongodb']['version'] }} multiverse
    - file: /etc/apt/sources.list.d/mongodb-org-{{ pillar['mongodb']['version'] }}.list
    - key_url: https://www.mongodb.org/static/pgp/server-{{ pillar['mongodb']['version'] }}.asc
install_5:
  pkg.installed:
    - refresh: True
    - pkgs: 
        - mongodb-org
install_6:
  cmd.run:
    - name: 'systemctl enable mongod.service'
install_7:
  service.running:
    - name: mongod
    - enable: True
mongouser_admin:
  mongodb_user.present:
  - name:     {{ pillar['mongodb']['admin']['user'] }}
  - passwd:   {{ pillar['mongodb']['admin']['password'] }}
      {%- set auth_status = salt['cmd.shell']("cat /etc/mongod.conf | grep 'authorization:' | awk {'print $2'}") %}
      {%- if auth_status == '"enabled"' %}
  - user:     {{ pillar['mongodb']['admin']['user'] }}
  - password: {{ pillar['mongodb']['admin']['password'] }}
      {%- else %}
  - user:     ''
  - password: ''
      {%- endif %}
  - host:     {{ pillar['mongodb']['admin']['host'] }}
  - port:     {{ pillar['mongodb']['admin']['port'] }}
  - authdb:   {{ pillar['mongodb']['admin']['authdb'] }}
  - roles:    {{ pillar['mongodb']['admin']['roles'] }}
  - database: {{ pillar['mongodb']['admin']['database'] }}
auth_enable_1:
  file.append:
    - name: '/etc/mongod.conf'
    - text: |
        security:
            authorization: "enabled"
auth_enable_2:
  service.running:
    - name: mongod
    - reload: True
    {%- endif %}
  {%- endif %}
{% endif %}

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
