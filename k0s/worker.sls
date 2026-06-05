{%- set join_token = salt['pillar.get']('k0s:worker:join_token', '') %}
{%- set api_address = salt['pillar.get']('k0s:worker:api_address', '') %}
{%- set profile = salt['pillar.get']('k0s:worker:profile', 'default') %}
{%- set data_dir = salt['pillar.get']('k0s:data_dir', '/var/lib/k0s') %}
{%- set extra_args = salt['pillar.get']('k0s:extra_args', '') %}
{%- set token_dir = '/etc/k0s' %}
{%- set token_file = token_dir ~ '/join-token' %}

{%- if not join_token %}
k0s_worker_join_token_required:
  test.fail_without_changes:
    - name: Pillar k0s.worker.join_token is required for the worker role.
{%- endif %}

{%- if not api_address %}
k0s_worker_api_address_required:
  test.fail_without_changes:
    - name: Pillar k0s.worker.api_address is required for the worker role.
{%- endif %}

{%- if join_token and api_address %}
include:
  - k0s.install

k0s_worker_token_directory:
  file.directory:
    - name: {{ token_dir }}
    - user: root
    - group: root
    - mode: '0755'

k0s_worker_join_token:
  file.managed:
    - name: {{ token_file }}
    - contents: {{ join_token | yaml }}
    - user: root
    - group: root
    - mode: '0600'
    - require:
      - file: k0s_worker_token_directory

k0s_worker_unit:
  k0s_worker.installed:
    - name: k0sworker
    - token_file: {{ token_file | yaml }}
    - api_server: {{ ('https://' ~ api_address) | yaml }}
    - profile: {{ profile | yaml }}
    - data_dir: {{ data_dir | yaml }}
    - extra_args: {{ extra_args | yaml }}
    - require:
      - file: k0s_binary_install
      - file: k0s_worker_join_token
{%- endif %}
