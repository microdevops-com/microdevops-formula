{%- set token_path = salt['pillar.get']('k0s:token:path', '/etc/k0s/worker-join-token') %}
{%- set token_ttl = salt['pillar.get']('k0s:token:ttl', 24) | int %}
{%- set token_dir = salt['file.dirname'](token_path) %}
{%- set role = salt['pillar.get']('k0s:role', 'single') %}

{%- if role == 'single' %}
k0s_worker_join_token_unsupported_single_role:
  test.fail_without_changes:
    - name: k0s.token cannot create worker join tokens for k0s single-node clusters.
{%- else %}

include:
  - k0s.install

k0s_token_directory:
  file.directory:
    - name: {{ token_dir | yaml }}
    - user: root
    - group: root
    - mode: '0755'

k0s_worker_join_token_create:
  k0s_token.created:
    - name: {{ token_path | yaml }}
    - ttl: {{ token_ttl }}
    - role: worker
    - require:
      - file: k0s_binary_install
      - file: k0s_token_directory

k0s_worker_join_token_file:
  file.managed:
    - name: {{ token_path | yaml }}
    - user: root
    - group: root
    - mode: '0600'
    - replace: False
    - require:
      - k0s_token: k0s_worker_join_token_create
{%- endif %}
