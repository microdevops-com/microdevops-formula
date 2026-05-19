{% if pillar["rabbitmq"] is defined %}

  {% from "acme/macros.jinja" import verify_and_issue %}

# Short hostname must be resolved to the same host, otherwise it will fail to start.
# rabbitmq1 -> other server
# rabbitmq1.xxx.domain.com -> this server
# => fail
# Use grains["host"] for short name.
rabbit_hosts:
  host.present:
  {%- if "local_ip" in pillar["rabbitmq"] %}
    - ip: {{ pillar["rabbitmq"]["local_ip"] }}
  {%- else %}
    - ip: 127.0.1.1
  {%- endif %}
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
    - creates:
        - /usr/share/keyrings/com.rabbitmq.team.gpg

  file.managed:
    - name: /etc/apt/sources.list.d/rabbitmq.list
    - contents: |
        ## Modern Erlang/OTP releases
        ##
        deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb1.rabbitmq.com/rabbitmq-erlang/{{ grains["os"].lower() }}/{{ grains["oscodename"] }} {{ grains["oscodename"] }} main
        deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb2.rabbitmq.com/rabbitmq-erlang/{{ grains["os"].lower() }}/{{ grains["oscodename"] }} {{ grains["oscodename"] }} main

        ## Provides modern RabbitMQ releases
        ##
        deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb1.rabbitmq.com/rabbitmq-server/{{ grains["os"].lower() }}/{{ grains["oscodename"] }} {{ grains["oscodename"] }} main
        deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb2.rabbitmq.com/rabbitmq-server/{{ grains["os"].lower() }}/{{ grains["oscodename"] }} {{ grains["oscodename"] }} main

  {#- Optional: enable all feature flags on the currently-installed broker before any
      upgrade. Required before upgrading to a major RabbitMQ version that drops support
      for older feature-flag states. Safe no-op on fresh installs (onlyif skips when the
      broker is not yet up). #}
  {%- if pillar["rabbitmq"].get("enable_all_feature_flag", False) %}
rabbit_enable_feature_flag:
  cmd.run:
    - name: rabbitmqctl enable_feature_flag all
    - onlyif: rabbitmqctl status 2>/dev/null | grep -q Uptime
  {%- endif %}

rabbit_pkg:
  {%- if "version" in pillar["rabbitmq"] %}
    {%- if pillar["rabbitmq"]["version"] == "latest" %}
  pkg.latest:
    - refresh: True
    - pkgs:
        - rabbitmq-server
    {%- else %}
  pkg.installed:
    - refresh: True
    - pkgs:
        - rabbitmq-server: '{{ pillar["rabbitmq"]["version"] }}*'
    {%- endif %}
  {%- else %}
  pkg.installed:
    - refresh: True
    - pkgs:
        - rabbitmq-server
  {%- endif %}
    - reload_modules: True

  {%- if "rabbitmq_management" in pillar["rabbitmq"].get("plugins", []) and pillar["rabbitmq"]["management_domain"] is defined %}

    {%- set domains = pillar["rabbitmq"]["management_domain"] ~ " " ~ pillar["rabbitmq"].get("subjectAltNames","") -%}

    {{ verify_and_issue(pillar["rabbitmq"]["acme_account"], "rabbitmq", domains) }}

rabbit_cert_perm_1:
  file.managed:
    - name: /opt/acme/cert/rabbitmq_{{ pillar["rabbitmq"]["management_domain"] }}_key.key
    - mode: 644
  {%- endif %}

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
  {%- if "rabbitmq_management" in pillar["rabbitmq"].get("plugins", []) and pillar["rabbitmq"]["management_domain"] is defined %}
        management.ssl.port = {{ pillar["rabbitmq"]["management_port"] }}
        management.ssl.cacertfile = /opt/acme/cert/rabbitmq_{{ pillar["rabbitmq"]["management_domain"] }}_ca.cer
        management.ssl.certfile = /opt/acme/cert/rabbitmq_{{ pillar["rabbitmq"]["management_domain"] }}_cert.cer
        management.ssl.keyfile = /opt/acme/cert/rabbitmq_{{ pillar["rabbitmq"]["management_domain"] }}_key.key
  {%- endif %}
  {%- for config_line in pillar["rabbitmq"].get("config", []) %}
        {{ config_line }}
  {%- endfor %}

rabbit_service_4:
  cmd.run:
    - name: systemctl daemon-reload

  {#- Download community plugin .ez files BEFORE the broker restart, so all .ez referenced
      by /etc/rabbitmq/enabled_plugins are on disk when the broker starts. Otherwise
      rabbitmq-plugins enable for any other plugin fails with plugins_not_found for the
      community ones that are already recorded as enabled. #}
  {%- for plugin in pillar["rabbitmq"].get("plugins", []) %}
    {%- if plugin is mapping %}
rabbit_plugin_{{ loop.index }}_download:
  cmd.run:
    - name: |
        set -eo pipefail
        RMQVER=$(dpkg-query -W -f='${Version}' rabbitmq-server | sed -E 's/^[0-9]+://;s/[-+~].*//')
        DEST_DIR="/usr/lib/rabbitmq/lib/rabbitmq_server-${RMQVER}/plugins"
        DEST_FILE="${DEST_DIR}/$(basename '{{ plugin["url"] }}')"
        # remove stale copies of this plugin from both the active versioned dir and the
        # system-wide /usr/lib/rabbitmq/plugins dir. -type f leaves bundled-plugin dirs
        # like amqp10_client-3.13.6/ untouched. ! -path "$DEST_FILE" preserves our target
        # if it is already at the requested version.
        # Default pattern is the safe `<name>-<digit>*` (versioned files only). Set
        # `force_cleanup: True` on the pillar entry to widen it to `<name>-*` so any file
        # with the plugin name prefix is removed (e.g. `<name>.bak`, `<name>-foo`).
        for D in "$DEST_DIR" "/usr/lib/rabbitmq/plugins"; do
          [ -d "$D" ] || continue
      {%- if plugin.get("force_cleanup", False) %}
          find "$D" -maxdepth 1 -type f -name '{{ plugin["name"] }}-*' ! -path "$DEST_FILE" -print -delete
      {%- else %}
          find "$D" -maxdepth 1 -type f -name '{{ plugin["name"] }}-[0-9]*' ! -path "$DEST_FILE" -print -delete
      {%- endif %}
        done
        if [ ! -f "$DEST_FILE" ]; then
          curl -fsSL -o "${DEST_FILE}.tmp" '{{ plugin["url"] }}'
          mv "${DEST_FILE}.tmp" "$DEST_FILE"
          chmod 644 "$DEST_FILE"
          echo "downloaded $(basename '{{ plugin["url"] }}')"
        fi
    - require:
      - pkg: rabbit_pkg
    {%- endif %}
  {%- endfor %}

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
  {%- if grains["oscodename"] in ["focal", "jammy", "bookworm", "noble", "trixie"] %}
        sed -i -e 's/check_user_login/user_login_authentication/' /usr/lib/python3/dist-packages/salt/modules/rabbitmq.py &&
  {%- else %}
        sed -i -e 's/check_user_login/user_login_authentication/' /usr/lib/python2.7/dist-packages/salt/modules/rabbitmq.py &&
  {%- endif %}
        timeout 2m bash -c 'salt-call saltutil.refresh_modules'; } || true

  {%- for plugin in pillar["rabbitmq"].get("plugins", []) %}
    {%- if plugin is mapping %}
rabbit_plugin_{{ loop.index }}:
  rabbitmq_plugin.enabled:
    - name: '{{ plugin["name"] }}'
    - require:
      - cmd: rabbit_plugin_{{ loop.index }}_download
    {%- else %}
rabbit_plugin_{{ loop.index }}:
  rabbitmq_plugin.enabled:
    - name: {{ plugin }}
    {%- endif %}
  {%- endfor %}

{% endif %}
