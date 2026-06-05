{%- set version = salt['pillar.get']('k0s:version', 'v1.30.2+k0s.0') %}
{%- set binary_url_override = salt['pillar.get']('k0s:install:binary_url', '') %}
{%- set checksum = salt['pillar.get']('k0s:install:checksum', '') %}
{%- set osarch = grains.get('osarch', '') %}
{%- set arch_map = {
  'amd64': 'amd64',
  'arm64': 'arm64',
  'aarch64': 'arm64',
} %}
{%- set k0s_arch = arch_map.get(osarch) %}

{%- if not k0s_arch %}
k0s_install_unsupported_architecture:
  test.fail_without_changes:
    - name: Unsupported k0s architecture '{{ osarch }}'
{%- else %}
{%- set binary_name = 'k0s-' ~ version ~ '-' ~ k0s_arch %}
{%- set binary_url = binary_url_override or 'https://github.com/k0sproject/k0s/releases/download/' ~ version ~ '/' ~ binary_name %}
{%- set tmp_path = '/tmp/' ~ binary_name %}
{%- set installed_version_matches = "test -x /usr/local/bin/k0s && /usr/local/bin/k0s version 2>/dev/null | grep -F -- '" ~ version ~ "'" %}

k0s_binary_download:
  file.managed:
    - name: {{ tmp_path }}
    - source: {{ binary_url }}
    - user: root
    - group: root
    - mode: '0755'
    - unless: {{ installed_version_matches }}
{%- if checksum %}
    - source_hash: sha256={{ checksum }}
{%- else %}
    - skip_verify: True
{%- endif %}

k0s_binary_install:
  file.copy:
    - name: /usr/local/bin/k0s
    - source: {{ tmp_path }}
    - force: True
    - user: root
    - group: root
    - mode: '0755'
    - unless: {{ installed_version_matches }}
    - require:
      - file: k0s_binary_download

k0s_binary_permissions:
  file.managed:
    - name: /usr/local/bin/k0s
    - create: False
    - replace: False
    - user: root
    - group: root
    - mode: '0755'
    - require:
      - file: k0s_binary_install
{%- endif %}
