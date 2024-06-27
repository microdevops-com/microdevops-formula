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
    - contents: {{ docker_ce.get("daemon_json","") | yaml_encode }}

docker-ce_repo_keyringdir:
  file.directory:
    - name: /etc/apt/keyrings
    - user: root
    - group: root

docker-ce_repo:
        {% if grains["os"] == "Debian" %}
{% set opts  = {"keyurl":"https://download.docker.com/linux/debian/gpg",
                "listfile":"/etc/apt/sources.list.d/docker-ce.list",
                "keyfile":"/etc/apt/keyrings/docker-ce.gpg"} %}
	{% else %}
{% set opts  = {"keyurl":"https://download.docker.com/linux/ubuntu/gpg",
                "listfile":"/etc/apt/sources.list.d/docker-ce.list",
                "keyfile":"/etc/apt/keyrings/docker-ce.gpg"} %}
	{% endif %}
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
        {% if grains["os"] == "Debian" %}
        deb [arch={{ grains["osarch"] }} signed-by={{ opts["keyfile"] }}] https://download.docker.com/linux/debian {{ grains['oscodename'] }} stable
	{% else %}
        deb [arch={{ grains["osarch"] }} signed-by={{ opts["keyfile"] }}] https://download.docker.com/linux/ubuntu {{ grains['oscodename'] }} stable
	{% endif %}

docker-ce_pkg:
  {%- if docker_ce["version"] == "latest" %}
  pkg.latest:
    - refresh: True
    - pkgs:
      - python3-docker
      - docker-ce
  {%- else %}
  pkg.installed:
    - refresh: True
    - pkgs:
      - python3-docker
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
