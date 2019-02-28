{% if pillar['alerta-urlmon'] is defined and pillar['alerta-urlmon'] is not none and pillar['alerta-urlmon']['checks'] is defined and pillar['alerta-urlmon']['checks'] is not none %}

alerta-urlmon_conf:
  file.managed:
    - name: /opt/alerta/urlmon/settings.py
    - user: alerta-urlmon
    - group: alerta-urlmon
    - mode: 660
    - contents: |
        # This file is managed by Salt, changes will be overwritten
        ENDPOINT = "{{ pillar['alerta-urlmon']['global_endpoint'] }}"
        API_KEY = "{{ pillar['alerta-urlmon']['global_api_key'] }}"
        checks = [
  {%- for group, checks in pillar['alerta-urlmon']['checks'].items()|sort %}
    {%- for check in checks %}
      {%- for from in check['from'] %}
        {%- if grains['fqdn'] == from['host'] %}
            {
                "resource": "{{ check['resource'] }}",
                "url": "{{ check['url'] }}",
                "environment": "{{ check['environment'] }}",
                "service": [{%- for service in check['service'] %}"{{ service }}",{%- endfor %}],
                "check_ssl": {{ check['check_ssl']|default(False) }},
                {% if check['status_regex'] is defined and check['status_regex'] is not none %}"status_regex": "{{ check['status_regex'] }}",{%- endif %}
                {% if check['search'] is defined and check['search'] is not none %}"search": "{{ check['search'] }}",{%- endif %}
                {% if from['endpoint'] is defined and from['endpoint'] is not none %}"api_endpoint": "{{ from['endpoint'] }}",{%- endif %}
                {% if from['api_key'] is defined and from['api_key'] is not none %}"api_key": "{{ from['api_key'] }}",{%- endif %}
                {% if from['warning'] is defined and from['warning'] is not none %}"warning": {{ from['warning'] }},{%- endif %}
                {% if from['critical'] is defined and from['critical'] is not none %}"critical": {{ from['critical'] }},{%- endif %}
                {% if from['retries'] is defined and from['retries'] is not none %}"count": {{ from['retries'] }},{%- endif %}
                {% if check['ssl_warning'] is defined and check['ssl_warning'] is not none %}"ssl_warning": {{ check['ssl_warning'] }},{%- endif %}
                {% if check['ssl_critical'] is defined and check['ssl_critical'] is not none %}"ssl_critical": {{ check['ssl_critical'] }},{%- endif %}
            },
        {% endif %}
      {%- endfor %}
    {%- endfor %}
  {%- endfor %}
        ]
{% endif %}

reload_serice:
  cmd.run:
    - name: 'systemctl restart alerta-urlmon'
