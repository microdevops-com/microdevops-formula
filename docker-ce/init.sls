{% if pillar["docker-ce"] is defined %}
docker-ce_config_dir:
  file.directory:
    - name: /etc/docker
    - mode: 700

docker-ce_config_file:
  file.managed:
    - name: /etc/docker/daemon.json
    - contents: {{ pillar["docker-ce"]["daemon_json"] | yaml_encode }}

docker-ce_repo:
  {%- if grains["os"] == "CentOS" %}
  file.managed:
    - name: /etc/yum.repos.d/docker-ce.repo
    - source:
      - https://download.docker.com/linux/centos/docker-ce.repo
      - skip_verify: True
  {%- else %}
  pkgrepo.managed:
    - humanname: Docker CE Repository
    - name: deb [arch=amd64] https://download.docker.com/linux/ubuntu {{ grains['oscodename'] }} stable
    - file: /etc/apt/sources.list.d/docker-ce.list
    - key_url: https://download.docker.com/linux/ubuntu/gpg
  {%- endif %}

docker-ce_pkg:
  {%- if pillar["docker-ce"]["version"] == "latest" %}
  pkg.latest:
    - refresh: True
    - pkgs:
      - docker-ce
      - python3-docker
  {%- else %}
  pkg.installed:
    - refresh: True
    - pkgs:
      - docker-ce: '{{ pillar["docker-ce"]["version"] }}*'
      - python3-docker
  {%- endif %}

docker-ce_service:
  service.running:
    - name: docker

docker-ce_restart:
  cmd.run:
    - name: systemctl restart docker
    - onchanges:
      - file: /etc/docker/daemon.json

{% endif %}

