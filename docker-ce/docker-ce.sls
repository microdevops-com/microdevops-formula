{% if pillar["docker-ce"] is defined %}
  {%- set docker_ce = pillar["docker-ce"] %}
{% endif %}

{% if docker_ce is defined and "version" in docker_ce %}
docker-ce_config_dir:
  file.directory:
    - name: /etc/docker
    - mode: 700

docker-ce_config_file:
  file.managed:
    - name: /etc/docker/daemon.json
    - contents: {{ docker_ce["daemon_json"] | yaml_encode }}

docker-ce_repo:
{% set opts  = {"keyurl":"https://download.docker.com/linux/ubuntu/gpg",
                "listfile":"/etc/apt/sources.list.d/docker-ce.list",
                "keyfile":"/etc/apt/keyrings/docker-ce.gpg"} %}
  pkg.installed:
    - pkgs: [wget, gpg]

  cmd.run:
    - name: |
        {% if "keyid" in opts %}
        gpg --keyserver keyserver.ubuntu.com --recv-keys {{ opts["keyid"] }}
        gpg --batch --yes --no-tty --output {{ opts["keyfile"] }} --export {{ opts["keyid"] }}
        {% elif "keyurl" in opts %}
        wget -O /tmp/key.asc {{ opts["keyurl"] }}
        gpg --batch --yes --no-tty --dearmor --output {{ opts["keyfile"] }} /tmp/key.asc
        {% endif %}
    - creates: {{ opts["keyfile"] }}

  file.managed:
    - name: {{ opts["listfile"] }}
    - contents: |
        deb [arch={{ grains["osarch"] }} signed-by={{ opts["keyfile"] }}] https://download.docker.com/linux/ubuntu {{ grains['oscodename'] }} stable

docker-ce_pkg:
  pkg.latest:
    - refresh: True
    - pkgs:
      - python3-docker
  {%- if docker_ce["version"] == "latest" %}
      - docker-ce
  {%- else %}
      - docker-ce: '{{ docker_ce["version"] }}*'
  {%- endif %}

docker-ce_service:
  service.running:
    - name: docker

docker-ce_restart:
  cmd.run:
    - name: systemctl restart docker
    - onchanges:
      - file: /etc/docker/daemon.json
{%- endif %}
