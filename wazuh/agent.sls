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
{% endif %}
