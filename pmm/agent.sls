{%- if pillar["pmm_agent"] is defined %}
{% set pmm_host = salt['pillar.get']('pmm_agent:pmm_host') %}
{% set pmm_user = salt['pillar.get']('pmm_agent:pmm_user', 'admin') %}
{% set pmm_password = salt['pillar.get']('pmm_agent:pmm_password') %}


configure repositories:
  pkg.installed:
    - sources:
      - percona-release: 'https://repo.percona.com/apt/percona-release_latest.generic_all.deb'

install pmm agent:
  pkg.installed:
    - refresh: True
    - pkgs:
      - pmm2-client

setup pmm agent:
  cmd.run:
    - name: pmm-agent setup --server-address {{ pmm_host }} --server-username {{ pmm_user }} --server-password {{ pmm_password }} --force --server-insecure-tls


  {%- if pillar["pmm_agent"]["services"] is defined %}


    {%- if pillar["pmm_agent"]["services"]["mysql"] is defined and pillar["pmm_agent"]["services"]["mysql"]["enabled"] %}
    {% set mysql_user = salt['pillar.get']('pmm_agent:services:mysql:user', 'pmm') %}
    {% set mysql_password = salt['pillar.get']('pmm_agent:services:mysql:password') %}
    {% set mysql_socket = salt['pillar.get']('pmm_agent:services:mysql:socket', '$(mysql -s -e "select @@socket" | awk 2)') %}
    {% set pmm_users_existence = salt["cmd.shell"]('mysql -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = \'{{ pmm_user }}\')"') %}

      {% if pmm_users_existence == 0 %}
create pmm user in mysql:
  cmd.run:
    - name: mysql -e "CREATE USER '{{ mysql_user }}'@'localhost' IDENTIFIED BY '{{ mysql_password }}';"
    - shell: /bin/bash
      {% else  %}
set password for pmm user in mysql:
  cmd.run:
    - name: mysql -e "ALTER USER '{{ mysql_user }}'@'localhost' IDENTIFIED BY '{{ mysql_password }}';"
    - shell: /bin/bash
      {% endif %}

mysql grant to {{ mysql_user }}@localhost:
  cmd.run:
    - name: mysql -e "GRANT SELECT, PROCESS, SUPER, REPLICATION CLIENT, RELOAD ON *.* TO '{{ mysql_user }}'@'localhost';"
    - shell: /bin/bash

mysql flush priviledges:
  cmd.run:
    - name: mysql -e "FLUSH PRIVILEGES;"
    - shell: /bin/bash

pmm-admin add mysql service:
  cmd.run:
    - name: pmm-admin add mysql --socket={{ mysql_socket }} --username={{ mysql_user }} --password={{ mysql_password }} --query-source=perfschema
    - shell: /bin/bash
    {%- endif %}


    {%- if pillar["pmm_agent"]["services"]["haproxy"] is defined and pillar["pmm_agent"]["services"]["haproxy"]["enabled"] %}
    {% set haproxy_port = salt['pillar.get']('pmm_agent:services:haproxy:port') %}
pmm-admin add haproxy service:
  cmd.run:
    - name: pmm-admin add haproxy --listen-port={{ haproxy_port }} 
    - shell: /bin/bash
    {%- endif %}


    {%- if pillar["pmm_agent"]["services"]["mongodb"] is defined and pillar["pmm_agent"]["services"]["mongodb"]["enabled"] %}
    {% set mongodb_user = salt['pillar.get']('pmm_agent:services:mongodb:user', 'mongoadmin') %}
    {% set mongodb_password = salt['pillar.get']('pmm_agent:services:mongodb:password') %}

      {%- if pillar["pmm_agent"]["services"]["mongodb"]["cluster"] is defined %}
    {% set mongodb_cluster = salt['pillar.get']('pmm_agent:services:mongodb:cluster') %}
pmm-admin add mongodb service:
  cmd.run:
    - name: pmm-admin add mongodb --username={{ mongodb_user }} --password={{ mongodb_password }}  --query-source=profiler --cluster={{ mongodb_cluster }}
    - shell: /bin/bash
      {%- else %}
pmm-admin add mongodb service:
  cmd.run:
    - name: pmm-admin add mongodb --username={{ mongodb_user }} --password={{ mongodb_password }}  --query-source=profiler
    - shell: /bin/bash
      {%- endif %}

    {%- endif %}


  {%- endif %}


{%- endif %}
