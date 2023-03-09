{% if pillar["pmm"] is defined %}

  {%- if pillar["docker-ce"] is defined %}

{% include "docker-ce/init.sls" with context %}

docker_pip_install:
  pip.installed:
    - name: docker-py >= 1.10
    - reload_modules: True
  {%- endif %}

percona_pmm_image:
  cmd.run:
    - name: docker pull {{ pillar["pmm"]["image"] }}

{% include "pmm/data_container_init.sls" with context %}
{% include "pmm/install_include.sls" with context %}
{% include "pmm/provisioning.sls" with context %}

{% endif %}
