{%- set manifests = salt['pillar.get']('k0s:manifests', []) %}
{%- set binary = salt['pillar.get']('k0s:binary', '/usr/local/bin/k0s') %}

{%- for manifest in manifests %}
k0s_manifest_{{ manifest.name | default('manifest_' + loop.index | string) }}:
  k0s_manifest.applied:
    - name: {{ manifest.name | default('manifest-' + loop.index | string) }}
    - binary: {{ binary }}
    {%- if manifest.source is defined %}
    - source: {{ manifest.source }}
    {%- endif %}
    {%- if manifest.content is defined %}
    - content: |
        {{ manifest.content | indent(8) }}
    {%- endif %}
{%- endfor %}