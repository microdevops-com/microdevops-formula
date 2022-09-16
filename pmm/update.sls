{% if pillar["pmm"] is defined %}
percona_pmm_image:
  cmd.run:
    - name: docker pull {{ pillar["pmm"]["image"] }}

  {%- include "pmm/install_include.sls" with context %}
  {%- include "pmm/provisioning.sls" with context %}

{% endif %}
