{%- set config_path = salt['pillar.get']('k0s:config_path', '/etc/k0s/k0s.yaml') %}
{%- set data_dir = salt['pillar.get']('k0s:data_dir', '/var/lib/k0s') %}
{%- set extra_args = salt['pillar.get']('k0s:extra_args', '') %}
{%- set role = salt['pillar.get']('k0s:role', 'single') %}
{%- set single = role == 'single' %}
{%- set enable_worker = salt['pillar.get']('k0s:controller:enable_worker', false) %}
{%- set no_taints = salt['pillar.get']('k0s:controller:no_taints', false) %}

include:
  - k0s.config

k0s_controller_unit:
  k0s_controller.installed:
    - name: k0scontroller
    - config: {{ config_path }}
    - data_dir: {{ data_dir }}
    - single: {{ single }}
    - enable_worker: {{ enable_worker }}
    - no_taints: {{ no_taints }}
    - extra_args: {{ extra_args | yaml }}
    - require:
      - file: k0s_binary_install
      - file: k0s_config_file
