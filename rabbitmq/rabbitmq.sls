{% if pillar['rabbitmq'] is defined and pillar['rabbitmq'] is not none %}

  {%- if (grains['oscodename'] == 'xenial') %}
erlang_repo_pkg:
  pkg.installed:
    - sources:
        - erlang-solutions: 'salt://pkg/files/erlang-solutions_1.0_all.deb'
  {%- elif grains['oscodename'] == 'bionic' %}
erlang_repo_pkg_for_bionic:
  pkg.installed:
    - sources:
        - erlang-solutions: 'https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb'
  {%- endif %}

erlang_pkg:
  pkg.latest:
    - pkgs:
        - erlang-nox

rabbit_repo:
  pkgrepo.managed:
    - humanname: RabbitMQ Repository
    - name: deb https://dl.bintray.com/rabbitmq/debian {{ grains['oscodename'] }} main
    - file: /etc/apt/sources.list.d/rabbitmq.list
    - key_url: https://github.com/rabbitmq/signing-keys/releases/download/2.0/rabbitmq-release-signing-key.asc

rabbit_pkg:
  pkg.latest:
    - pkgs:
        - rabbitmq-server
    - reload_modules: True

  {% if 'rabbitmq_management' in pillar['rabbitmq'].get('plugins', []) and pillar['rabbitmq']['management_domain'] is defined and pillar['rabbitmq']['management_domain'] is not none %}
rabbit_cert_for_management:
  cmd.run:
    - shell: /bin/bash
    - name: 'openssl verify -CAfile /opt/acme/cert/rabbitmq_ca.cer /opt/acme/cert/rabbitmq_fullchain.cer 2>&1 | grep -q -i -e error; [ ${PIPESTATUS[1]} -eq 0 ] && /opt/acme/home/acme_local.sh --cert-file /opt/acme/cert/rabbitmq_cert.cer --key-file /opt/acme/cert/rabbitmq_key.key --ca-file /opt/acme/cert/rabbitmq_ca.cer --fullchain-file /opt/acme/cert/rabbitmq_fullchain.cer --issue -d {{ pillar['rabbitmq']['management_domain'] }} || true'

rabbit_cert_perm_1:
  file.managed:
    - name: /opt/acme/cert/rabbitmq_key.key
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
  {% if 'rabbitmq_management' in pillar['rabbitmq'].get('plugins', []) and pillar['rabbitmq']['management_domain'] is defined and pillar['rabbitmq']['management_domain'] is not none %}
        management.listener.ssl = true
        management.listener.ssl_opts.cacertfile = /opt/acme/cert/rabbitmq_ca.cer
        management.listener.ssl_opts.certfile = /opt/acme/cert/rabbitmq_cert.cer
        management.listener.ssl_opts.keyfile = /opt/acme/cert/rabbitmq_key.key
  {% endif %}
  {%- for config_line in pillar['rabbitmq'].get('config', []) %}
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
    - name: 'until rabbitmqctl status | grep -q "Uptime"; do echo .; done'

  {%- for vhost in pillar['rabbitmq'].get('vhosts', []) %}
rabbit_vhost_{{ loop.index }}:
    {%- if vhost['present'] is defined and vhost['present'] is not none and vhost['present'] %}
  rabbitmq_vhost.present:
    {%- elif vhost['absent'] is defined and vhost['absent'] is not none and vhost['absent'] %}
  rabbitmq_vhost.absent:
    {%- endif %}
    - name: '{{ vhost['name'] }}'
  {%- endfor %}

rabbit_user_guest_absent:
  rabbitmq_user.absent:
    - name: 'guest'

rabbit_user_admin_present:
  rabbitmq_user.present:
    - name: {{ pillar['rabbitmq']['admin']['name'] }}
    - password: {{ pillar['rabbitmq']['admin']['password'] }}
    - force: True
    - tags: administrator
    - perms:
        - '/':
            - '.*'
            - '.*'
            - '.*'
  {%- for vhost in pillar['rabbitmq'].get('vhosts', []) %}
    {%- if vhost['present'] is defined and vhost['present'] is not none and vhost['present'] %}
        - '{{ vhost['name'] }}':
            - '.*'
            - '.*'
            - '.*'
    {%- endif %}
  {%- endfor %}

  {%- for user in pillar['rabbitmq'].get('users', []) %}
rabbit_user_{{ loop.index }}:
    {%- if user['present'] is defined and user['present'] is not none and user['present'] %}
  rabbitmq_user.present:
    - name: '{{ user['name'] }}'
    - password: {{ user['password'] }}
    - force: True
    - tags: {{ user.get('tags', []) }}
    - perms: {{ user.get('perms', []) }}
    {%- elif user['absent'] is defined and user['absent'] is not none and user['absent'] %}
  rabbitmq_user.absent:
    - name: '{{ user['name'] }}'
    {%- endif %}
  {%- endfor %}

  {%- for plugin in pillar['rabbitmq'].get('plugins', []) %}
rabbit_plugin_{{ loop.index }}:
  rabbitmq_plugin.enabled:
    - name: {{ plugin }}
  {%- endfor %}

  {%- for policy in pillar['rabbitmq'].get('policies', []) %}
rabbit_policy_{{ loop.index }}:
    {%- if policy['present'] is defined and policy['present'] is not none and policy['present'] %}
  rabbitmq_policy.present:
    - name: {{ policy['name'] }}
    - pattern: '{{ policy['pattern'] }}'
    - definition: '{{ policy['definition'] }}'
    - priority: {{ policy['priority'] }}
    - vhost: '{{ policy['vhost'] }}'
    - apply_to: '{{ policy['apply_to'] }}'
    {%- elif policy['absent'] is defined and policy['absent'] is not none and policy['absent'] %}
  rabbitmq_policy.absent:
    - name: {{ policy['name'] }}
    - vhost: '{{ policy['vhost'] }}'
    {%- endif %}
  {%- endfor %}

{% endif %}
