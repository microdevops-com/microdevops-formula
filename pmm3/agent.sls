{#-
  PMM 3 client (pmm-client package, pmm-agent systemd service) on the host.
  The agent is registered once: `pmm-admin config --force` re-creates the node and PMM drops its services,
  so it runs only when the agent is not registered to pmm3_agent:pmm_host. `pmm-admin add` - only when the service is missing.
-#}
{%- if pillar['pmm3_agent'] is defined %}
{%- set agent = pillar['pmm3_agent'] %}
{%- set pmm_host = agent['pmm_host'] %}
{%- set pmm_port = agent.get('pmm_port', 443) %}
{%- set pmm_user = agent.get('pmm_user', 'admin') %}
{%- set services = agent.get('services', {}) %}
{%- set agent_config = '/usr/local/percona/pmm/config/pmm-agent.yaml' %}
{#- pmm-admin names services <os hostname>-<type>; the name is set explicitly: <node_name>-mysql (alert rules match it),
    <node_name>-mongodb #}
{%- set service_prefix = agent.get('node_name') or grains['nodename'] %}

pmm3_agent_percona_release:
  pkg.installed:
    - sources:
      - percona-release: https://repo.percona.com/apt/percona-release_latest.generic_all.deb

pmm3_agent_repo:
  cmd.run:
    - name: percona-release enable pmm3-client
    - unless: grep -rqs pmm3-client /etc/apt/sources.list.d/
    - require:
      - pkg: pmm3_agent_percona_release

{#- pmm2-client conflicts with pmm-client #}
pmm3_agent_remove_pmm2_client:
  pkg.removed:
    - name: pmm2-client

pmm3_agent_package:
  pkg.installed:
    - name: pmm-client
    {%- if agent.get('version') %}
    - version: {{ agent['version'] }}
    {%- endif %}
    - refresh: True
    - require:
      - cmd: pmm3_agent_repo
      - pkg: pmm3_agent_remove_pmm2_client

pmm3_agent_service:
  service.running:
    - name: pmm-agent
    - enable: True
    - require:
      - pkg: pmm3_agent_package

pmm3_agent_setup:
  cmd.run:
    - name: >-
        pmm-admin config --server-insecure-tls --server-url="$PMM_SERVER_URL" --force
        {%- if agent.get('node_name') %} {{ agent.get('node_address', grains['fqdn_ip4'][0]) }} generic {{ agent['node_name'] }}{%- endif %}
    - env:
      - PMM_SERVER_URL: {{ ('https://' ~ pmm_user | urlencode ~ ':' ~ agent['pmm_password'] | urlencode ~ '@' ~ pmm_host ~ ':' ~ pmm_port) | json }}
    {#- registered = the config has an agent id and this server address. Not "Connected": a restart or a network
        blip would re-register the node and PMM would drop its services #}
    - unless: >-
        grep -qE '^id: *"?[^" ]+' {{ agent_config }} &&
        awk '$1 == "address:" { gsub(/"/, "", $2); if ($2 == "{{ pmm_host }}:{{ pmm_port }}") f = 1 } END { exit !f }' {{ agent_config }}
    - require:
      - service: pmm3_agent_service
{%- if services.get('mysql', {}).get('enabled') %}
{%- set mysql = services['mysql'] %}
{%- set mysql_user = mysql.get('user', 'pmm') %}
{%- set mysql_socket = mysql.get('socket', '$(mysql -sNe "select @@socket")') %}
{%- set mysql_service = service_prefix ~ '-mysql' %}
{#- pmm-admin names a service <os hostname>-<type> by default: the name of a former registration #}
{%- set mysql_former = grains['nodename'] ~ '-mysql' %}

pmm3_agent_mysql_user:
  cmd.run:
    - name: >-
        mysql -e "CREATE USER IF NOT EXISTS '{{ mysql_user }}'@'localhost' IDENTIFIED BY '$MYSQL_PMM_PASSWORD';
        ALTER USER '{{ mysql_user }}'@'localhost' IDENTIFIED BY '$MYSQL_PMM_PASSWORD';
        GRANT SELECT, PROCESS, SUPER, REPLICATION CLIENT, RELOAD ON *.* TO '{{ mysql_user }}'@'localhost';"
    - env:
      - MYSQL_PMM_PASSWORD: {{ mysql['password'] | json }}
      - MYSQL_PWD: {{ mysql['password'] | json }}
    - unless: mysql -u {{ mysql_user }} -e 'SELECT 1' > /dev/null 2>&1

{#- the user state changes only when the pillar password no longer works: the registered service still has the old one,
    remove it here and pmm3_agent_mysql_service adds it again with the new password #}
pmm3_agent_mysql_service_password:
  cmd.run:
    - name: pmm-admin remove mysql {{ mysql_service }}
    - onlyif: pmm-admin list | awk '$1 == "MySQL" && $2 == "{{ mysql_service }}" { f = 1 } END { exit !f }'
    - onchanges:
      - cmd: pmm3_agent_mysql_user
    - require:
      - cmd: pmm3_agent_setup

pmm3_agent_mysql_service:
  cmd.run:
    - name: >-
        pmm-admin add mysql --service-name={{ mysql_service }} --socket={{ mysql_socket }} --username={{ mysql_user }}
        --password="$MYSQL_PMM_PASSWORD" --query-source={{ mysql.get('query_source', 'perfschema') }}
    - env:
      - MYSQL_PMM_PASSWORD: {{ mysql['password'] | json }}
    - unless: pmm-admin list | awk '$1 == "MySQL" && $2 == "{{ mysql_service }}" { f = 1 } END { exit !f }'
    - require:
      - cmd: pmm3_agent_setup
      - cmd: pmm3_agent_mysql_user
      - cmd: pmm3_agent_mysql_service_password
{%- if mysql_former != mysql_service %}

{#- the former registration of this instance (<os hostname>-mysql on the same socket) is removed once the service is
    registered under the new name: pmm-admin add checks the connection, so a failed add (an outdated password) leaves
    the former one collecting. pmm-admin list: type, name, address (the socket, or host:port), id #}
pmm3_agent_mysql_service_former:
  cmd.run:
    - name: pmm-admin remove mysql {{ mysql_former }}
    - onlyif:
      - pmm-admin list | awk '$1 == "MySQL" && $2 == "{{ mysql_service }}" { f = 1 } END { exit !f }'
      - pmm-admin list | awk -v a="{{ mysql_socket }}" '$1 == "MySQL" && $2 == "{{ mysql_former }}" && $3 == a { f = 1 } END { exit !f }'
    - require:
      - cmd: pmm3_agent_mysql_service
{%- endif %}
{%- endif %}
{%- if services.get('haproxy', {}).get('enabled') %}

pmm3_agent_haproxy_service:
  cmd.run:
    - name: pmm-admin add haproxy --listen-port={{ services['haproxy']['port'] }}
    - unless: pmm-admin list | grep -qE '^HAProxy '
    - require:
      - cmd: pmm3_agent_setup
{%- endif %}
{%- if services.get('mongodb', {}).get('enabled') %}
{%- set mongodb = services['mongodb'] %}
{%- set mongodb_service = service_prefix ~ '-mongodb' %}
{%- set mongodb_host = mongodb.get('host', '127.0.0.1') %}
{%- set mongodb_port = mongodb.get('port', 27017) %}
{#- the address as pmm-admin list prints it: host:port, an IPv6 host in brackets #}
{%- set mongodb_address = ('[' ~ mongodb_host ~ ']' if ':' in mongodb_host else mongodb_host) ~ ':' ~ mongodb_port %}
{%- set mongodb_former = grains['nodename'] ~ '-mongodb' %}
{#- the defaults are those of the former formula (user mongoadmin, query source profiler), so an existing pillar
    registers the service as before. Recommended: user pmm (README), query_source none or mongolog.
    none - metrics only; mongolog - QAN from the slow operations in the mongod log (MongoDB 5.0+);
    profiler - QAN from system.profile, needs the profiler enabled in mongod #}
{%- set mongodb_query_source = mongodb.get('query_source', 'profiler') %}
{%- if mongodb_query_source not in ['none', 'mongolog', 'profiler'] %}
  {{ raise('pmm3_agent:services:mongodb:query_source must be none, mongolog or profiler, got ' ~ mongodb_query_source) }}
{%- endif %}

pmm3_agent_mongodb_service:
  cmd.run:
    - name: >-
        pmm-admin add mongodb --service-name={{ mongodb_service }}
        --host={{ mongodb_host }} --port={{ mongodb_port }}
        --username={{ mongodb.get('user', 'mongoadmin') }} --password="$MONGODB_PMM_PASSWORD"
        --query-source={{ mongodb_query_source }}
        {%- if mongodb.get('cluster') %} --cluster={{ mongodb['cluster'] }}{%- endif %}
        {%- if mongodb.get('replication_set') %} --replication-set={{ mongodb['replication_set'] }}{%- endif %}
        {%- if mongodb.get('environment') %} --environment={{ mongodb['environment'] }}{%- endif %}
    - env:
      - MONGODB_PMM_PASSWORD: {{ mongodb['password'] | json }}
    - unless: pmm-admin list | awk '$1 == "MongoDB" && $2 == "{{ mongodb_service }}" { f = 1 } END { exit !f }'
    - require:
      - cmd: pmm3_agent_setup
{%- if mongodb_former != mongodb_service %}

{#- the former registration of this instance (<os hostname>-mongodb at the same host:port) is removed once the service
    is registered under the new name: pmm-admin add checks the connection, a failed add leaves the former one collecting #}
pmm3_agent_mongodb_service_former:
  cmd.run:
    - name: pmm-admin remove mongodb {{ mongodb_former }}
    - onlyif:
      - pmm-admin list | awk '$1 == "MongoDB" && $2 == "{{ mongodb_service }}" { f = 1 } END { exit !f }'
      - pmm-admin list | awk -v a="{{ mongodb_address }}" '$1 == "MongoDB" && $2 == "{{ mongodb_former }}" && $3 == a { f = 1 } END { exit !f }'
    - require:
      - cmd: pmm3_agent_mongodb_service
{%- endif %}
{%- endif %}
{%- endif %}
