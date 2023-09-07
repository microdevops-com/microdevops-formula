{% if  pillar["wazuhagent"] is defined %}
set_env_MAZUH_MANAGER:
  environ.setenv:
    - name: WAZUH_MANAGER
    - value: {{ pillar["wazuhagent"]["manager"] }}
set_env_WAZUH_AGENT_GROUP:
  environ.setenv:
    - name: WAZUH_AGENT_GROUP
    - value: {{ pillar["wazuhagent"]["group"] | default('default') }}
{#
wazuh_agent_install:
  pkg.installed:
    - sources:
      - wazuh_agent: {{ pillar["wazuhagent"]["deb"] }} 
    - refresh: True
    - skip_verify: True
#}

wazuh_agent_install:
  cmd.run:
    - name: "curl -so wazuh-agent.deb {{ pillar["wazuhagent"]["deb"] }} && sudo WAZUH_MANAGER='{{ pillar["wazuhagent"]["manager"] }}' dpkg -i ./wazuh-agent.deb && systemctl daemon-reload"

wazuh_agent_service_start:
  service.running:
    - name: wazuh-agent
    - enable: True

  {%- if  pillar["wazuhagent"]["suricata"] | default(false) %}
create_an_auxiliary_script:
  file.managed:
    - name: /tmp/auxiliar-script.sh
    - contents: |
        import os
        # Шлях до конфігураційного файлу ossec.conf
        ossec_config_file = "/var/ossec/etc/ossec.conf"
        # Текст блоку, який ми хочемо додати
        localfile_block = """
          <localfile>
            <log_format>json</log_format>
            <location>/var/log/suricata/eve.json</location>
          </localfile>
        """
        # Відкриваємо файл для читання
        with open(ossec_config_file, "r") as f:
            file_content = f.read()
        # Перевіряємо, чи блок <localfile> вже присутній у файлі (без врахування пробілів)
        if localfile_block.replace(" ", "") not in file_content.replace(" ", ""):
            # Знаходимо останній розділ </ossec_config>
            last_ossec_config_index = file_content.rfind("</ossec_config>")
            # Якщо останній розділ знайдено
            if last_ossec_config_index != -1:
                # Додаємо блок <localfile> перед останнім розділом
                updated_file_content = file_content[:last_ossec_config_index] + localfile_block + file_content[last_ossec_config_index:]
                # Записуємо зміни назад у файл
                with open(ossec_config_file, "w") as f:
                    f.write(updated_file_content)

exec_an_auxiliary_script:
  cmd.run:
    - name: "python3 /tmp/auxiliar-script.sh"
    - require:
      - file: create_an_auxiliary_script

restart_wazuh-agent_service:
  cmd.run:
    - name: "systemctl restart wazuh-agent"
    - require:
      - cmd: exec_an_auxiliary_script
  {%- endif %}
{% endif %}
