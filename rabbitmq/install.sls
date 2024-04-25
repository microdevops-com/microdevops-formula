{% if pillar["rabbitmq"] is defined %}

  {% from "acme/macros.jinja" import verify_and_issue %}


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

rabbitmq_rm_legacy_erlang_list:
  file.absent:
    - name: /etc/apt/sources.list.d/erlang-solutions.list

rabbitmq_repo:
  pkg.installed:
    - pkgs: [wget, gpg]

  cmd.run:
    - name: |
        curl -1sLf https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA |  gpg --dearmor > /usr/share/keyrings/com.rabbitmq.team.gpg
        curl -1sLf https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-erlang.E495BB49CC4BBE5B.key | gpg --dearmor > /usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg
        curl -1sLf https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key | gpg --dearmor > /usr/share/keyrings/rabbitmq.9F4587F226208342.gpg
    - creates:
        - /usr/share/keyrings/com.rabbitmq.team.gpg
        - /usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg
        - /usr/share/keyrings/rabbitmq.9F4587F226208342.gpg

  file.managed:
    - name: /etc/apt/sources.list.d/rabbitmq.list
    - contents: |
        ## Provides modern Erlang/OTP releases
        ##
        deb [signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq-erlang/deb/ubuntu {{ grains["oscodename"] }} main
        deb-src [signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq-erlang/deb/ubuntu {{ grains["oscodename"] }} main
        # another mirror for redundancy
        deb [signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa2.novemberain.com/rabbitmq/rabbitmq-erlang/deb/ubuntu {{ grains["oscodename"] }} main
        deb-src [signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa2.novemberain.com/rabbitmq/rabbitmq-erlang/deb/ubuntu {{ grains["oscodename"] }} main

        ## Provides RabbitMQ
        ##
        deb [signed-by=/usr/share/keyrings/rabbitmq.9F4587F226208342.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq-server/deb/ubuntu {{ grains["oscodename"] }} main
        deb-src [signed-by=/usr/share/keyrings/rabbitmq.9F4587F226208342.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq-server/deb/ubuntu {{ grains["oscodename"] }} main
        # another mirror for redundancy
        deb [signed-by=/usr/share/keyrings/rabbitmq.9F4587F226208342.gpg] https://ppa2.novemberain.com/rabbitmq/rabbitmq-server/deb/ubuntu {{ grains["oscodename"] }} main
        deb-src [signed-by=/usr/share/keyrings/rabbitmq.9F4587F226208342.gpg] https://ppa2.novemberain.com/rabbitmq/rabbitmq-server/deb/ubuntu {{ grains["oscodename"] }} main

rabbit_pkg:
  pkg.latest:
    - refresh: True
    - pkgs:
        - rabbitmq-server
    - reload_modules: True

  {% if "rabbitmq_management" in pillar["rabbitmq"].get("plugins", []) and pillar["rabbitmq"]["management_domain"] is defined %}

    {%- set domains = pillar["rabbitmq"]["management_domain"] ~ " " ~ pillar["rabbitmq"].get("subjectAltNames","") -%}

    {{ verify_and_issue(pillar["rabbitmq"]["acme_account"], "rabbitmq", domains) }}

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
  {%- if grains["oscodename"] in ["focal", "jammy", "bookworm"] %}
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
