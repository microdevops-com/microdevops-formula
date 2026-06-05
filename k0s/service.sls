{%- set role = salt['pillar.get']('k0s:role', 'single') %}
{%- set service_enabled = salt['pillar.get']('k0s:service:enabled', true) %}
{%- set service_running = salt['pillar.get']('k0s:service:running', true) %}
{%- set service_name_by_role = {
  'controller': 'k0scontroller',
  'single': 'k0scontroller',
  'worker': 'k0sworker',
} %}
{%- set service_name = service_name_by_role.get(role) %}
{%- set worker_join_token = salt['pillar.get']('k0s:worker:join_token', '') %}
{%- set worker_api_address = salt['pillar.get']('k0s:worker:api_address', '') %}
{%- set worker_unit_available = role != 'worker' or (worker_join_token and worker_api_address) %}

{%- if role in ['controller', 'single'] %}
include:
  - k0s.controller
{%- elif role == 'worker' %}
include:
  - k0s.worker
{%- endif %}

{%- if not service_name %}
k0s_service_unknown_role:
  test.fail_without_changes:
    - name: Unsupported k0s role '{{ role }}'
{%- elif worker_unit_available and service_running %}
k0s_service:
  service.running:
    - name: {{ service_name }}
    - enable: {{ service_enabled }}
    - watch:
      - file: k0s_binary_install
{%- if role in ['controller', 'single'] %}
      - file: k0s_config_file
    - require:
      - k0s_controller: k0s_controller_unit
{%- else %}
    - require:
      - k0s_worker: k0s_worker_unit
{%- endif %}

{%- if role in ['controller', 'single'] %}
k0s_controller_operational:
  k0s_cluster.operational:
    - name: k0s
    - timeout: 120
    - interval: 5
    - require:
      - service: k0s_service
{%- endif %}
{%- elif worker_unit_available %}
k0s_service:
  service.dead:
    - name: {{ service_name }}
    - enable: {{ service_enabled }}
{%- if role in ['controller', 'single'] %}
    - require:
      - k0s_controller: k0s_controller_unit
{%- else %}
    - require:
      - k0s_worker: k0s_worker_unit
{%- endif %}
{%- endif %}
