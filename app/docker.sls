{% if pillar['app'] is defined and pillar['app'] is not none and pillar['app']['docker'] is defined and pillar['app']['docker'] is not none %}
docker_install_00:
  file.directory:
    - name: /etc/docker
    - mode: 700

docker_install_01:
  file.managed:
    - name: /etc/docker/daemon.json
    - contents: |
        {"iptables": false}

docker_install_1:
  pkgrepo.managed:
    - humanname: Docker CE Repository
    - name: deb [arch=amd64] https://download.docker.com/linux/{{ grains['os']|lower }} {{ grains['oscodename'] }} stable
    - file: /etc/apt/sources.list.d/docker-ce.list
    - key_url: https://download.docker.com/linux/{{ grains['os']|lower }}/gpg

docker_install_2:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - docker-ce: '{{ pillar['app']['docker']['docker-ce_version'] }}*'
        - python-pip

docker_pip_install:
  pip.installed:
    - name: docker-py >= 1.10
    - reload_modules: True

docker_purge_apparmor:
  pkg.purged:
    - name: apparmor

docker_install_3:
  service.running:
    - name: docker

docker_install_4:
  cmd.run:
    - name: 'systemctl restart docker'
    - onchanges:
        - file: /etc/docker/daemon.json
        - pkg: apparmor

  {%- for net in pillar['app']['docker']['networks'] %}
docker_network_{{ loop.index }}:
  docker_network.present:
    - name: {{ net }}
  {%- endfor %}

  {%- for app_name, app in pillar['app']['docker']['apps'].items() %}
    {%- if not (pillar['app']['docker']['deploy_only'] is defined and pillar['app']['docker']['deploy_only'] is not none) or app_name in pillar['app']['docker']['deploy_only'] %}
docker_app_dir_{{ loop.index }}:
  file.directory:
    - name: {{ app['home'] }}
    - mode: 755
    - makedirs: True

      {%- set i_loop = loop %}
      {%- for bind in app['binds'] %}
docker_app_bind_dir_{{ i_loop.index }}_{{ loop.index }}:
  file.directory:
    - name: {{ bind.split(':')[0] }}
    - mode: 755
    - makedirs: True
      {%- endfor %}

docker_app_container_{{ loop.index }}:
  docker_container.running:
    - name: app-{{ app_name }}
    - user: root
      {%- if pillar['image_override'] is defined and pillar['image_override'] is not none and pillar['image_override'][app_name] is defined and pillar['image_override'][app_name] is not none %}
    - image: {{ pillar['image_override'][app_name] }}
      {%- else %}
    - image: {{ app['image'] }}
      {%- endif %}
    - detach: True
    - restart_policy: unless-stopped
    - publish: {{ app['publish'] }}
    - environment: {{ app['environment'] }}
    - binds: {{ app['binds'] }}
    - networks: {{ app['networks'] }}
    {%- endif %}
  {%- endfor %}
{% endif %}
