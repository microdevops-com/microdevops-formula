{% if pillar["pmm"] is defined %}
  {% if pillar["docker-ce"] is defined %}
include:
 - docker-ce.init
docker_pip_install:
  pip.installed:
    - name: docker-py >= 1.10
    - reload_modules: True
  {% endif %}
percona_pmm_image:
  cmd.run:
    - name: docker pull {{ pillar["pmm"]["image"] }}
include:
 - pmm.data_container_init
 - pmm.install_include
 - pmm.provisioning
{% endif %}
