{% if pillar["rabbitmq"] is defined %}

# Short hostname must be resolved to the same host, otherwise it will fail to start.
# rabbitmq1 -> other server
# rabbitmq1.xxx.domain.com -> this server
# => fail
# Use grains["host"] for short name.
rabbit_hosts:
  host.present:
    - ip: 127.0.1.1
    - names:
      - {{ grains["host"] }}

erlang_repo:
  pkgrepo.managed:
    - humanname: Erlang Solutions
    - name: deb https://packages.erlang-solutions.com/ubuntu {{ grains["oscodename"] }} contrib
    - file: /etc/apt/sources.list.d/erlang-solutions.list
    - key_url: https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc
    - clean_file: True

erlang_pkg:
  pkg.latest:
    - refresh: True
    - pkgs:
        - erlang-nox
        - erlang-base

rabbit_repo:
  pkgrepo.managed:
    - humanname: RabbitMQ Repository
    - name: deb https://packagecloud.io/rabbitmq/rabbitmq-server/ubuntu/ {{ grains["oscodename"] }} main
    - file: /etc/apt/sources.list.d/rabbitmq.list
    - key_url: https://packagecloud.io/rabbitmq/rabbitmq-server/gpgkey
    - clean_file: True

rabbit_pkg:
  pkg.latest:
    - refresh: True
    - pkgs:
        - rabbitmq-server
    - reload_modules: True

  {% if "rabbitmq_management" in pillar["rabbitmq"].get("plugins", []) and pillar["rabbitmq"]["management_domain"] is defined %}
rabbit_cert_for_management:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["rabbitmq"]["acme_account"] }}/verify_and_issue.sh rabbitmq {{ pillar["rabbitmq"]["management_domain"] }} {%- if 'subjectAltNames' in pillar['rabbitmq'] %} {{ pillar['rabbitmq']['subjectAltNames'] }} {% endif %}"

rabbit_cert_perm_1:
  file.managed:
    - name: /opt/acme/cert/rabbitmq_{{ pillar["rabbitmq"]["management_domain"] }}_key.key
    - mode: 644
  {% endif %}

rabbit_service_1:
  file.directory:
    - name: /etc/systemd/system/rabbitmq-server.service.d
    - makedirs: True

rabbit_service_2:
  file.managed:
    - name: /etc/default/rabbitmq-server
    - contents: |
        ulimit -n 65536

rabbit_service_3:
  file.managed:
    - name: /etc/systemd/system/rabbitmq-server.service.d/limits.conf
    - contents: |
        [Service]
        LimitNOFILE=65536

rabbit_config_1:
  file.managed:
    - name: /etc/rabbitmq/rabbitmq.conf
    - user: root
    - group: rabbitmq
    - contents: |
        # This file is managed by Salt, changes will be overwritten
  {% if "rabbitmq_management" in pillar["rabbitmq"].get("plugins", []) and pillar["rabbitmq"]["management_domain"] is defined %}
        management.ssl.port = {{ pillar["rabbitmq"]["management_port"] }}
        management.ssl.cacertfile = /opt/acme/cert/rabbitmq_{{ pillar["rabbitmq"]["management_domain"] }}_ca.cer
        management.ssl.certfile = /opt/acme/cert/rabbitmq_{{ pillar["rabbitmq"]["management_domain"] }}_cert.cer
        management.ssl.keyfile = /opt/acme/cert/rabbitmq_{{ pillar["rabbitmq"]["management_domain"] }}_key.key
  {% endif %}
  {%- for config_line in pillar["rabbitmq"].get("config", []) %}
        {{ config_line }}
  {%- endfor %}

rabbit_service_4:
  cmd.run:
    - name: systemctl daemon-reload

rabbit_service_5:
  cmd.run:
    - name: service rabbitmq-server restart

rabbit_service_6:
  cmd.run:
    - name: |
        timeout 2m bash -c 'until rabbitmqctl status | grep -q "Uptime"; do echo .; sleep 1; done'

# If salt minion is malfunctioned salt-call will wait indefinetly, run with timeout
rabbit_fix_salt_module:
  cmd.run:
    - name: |
        [ -f /usr/lib/python3/dist-packages/salt/modules/rabbitmq.py ] && {
  {%- if grains["oscodename"] in ["focal", "jammy"] %}
        sed -i -e 's/check_user_login/user_login_authentication/' /usr/lib/python3/dist-packages/salt/modules/rabbitmq.py &&
  {%- else %}
        sed -i -e 's/check_user_login/user_login_authentication/' /usr/lib/python2.7/dist-packages/salt/modules/rabbitmq.py &&
  {%- endif %}
        timeout 2m bash -c 'salt-call saltutil.refresh_modules'; } || true

  {%- for plugin in pillar["rabbitmq"].get("plugins", []) %}
rabbit_plugin_{{ loop.index }}:
  rabbitmq_plugin.enabled:
    - name: {{ plugin }}
  {%- endfor %}

{% endif %}
