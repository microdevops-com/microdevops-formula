{% if pillar['pmm'] is defined %}

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
        - docker-ce: '{{ pillar['pmm']['docker-ce_version'] }}*'
        - python3-pip
                
docker_pip_install:
  pip.installed:
    - name: docker-py >= 1.10
    - reload_modules: True

docker_install_3:
  service.running:
    - name: docker

docker_install_4:
  cmd.run:
    - name: 'systemctl restart docker'
    - onchanges:
        - file: /etc/docker/daemon.json

acme_cert:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["pmm"]["acme_account"] }}/verify_and_issue.sh percona_pmm {{ pillar["pmm"]["servername"] }}"



{%- for domain in pillar['pmm']['domains'] %}
    {%- set i_loop = loop %}
    {%- for instance in domain['instances'] %}


percona_pmm_etc_dir_{{ loop.index }}_{{ i_loop.index }}:
  file.directory:
    - name: /opt/pmm/{{ domain['name'] }}/{{ instance['name'] }}/etc
    - mode: 755
    - makedirs: True


percona_pmm_config_{{ loop.index }}_{{ i_loop.index }}:
  file.managed:
    - name: /opt/pmm/{{ domain['name'] }}/{{ instance['name'] }}/etc/grafana.ini
    - user: root
    - group: root
    - mode: 644
    - contents: {{ instance['config'] | yaml_encode }}

percona_pmm_image_{{ loop.index }}_{{ i_loop.index }}:
  cmd.run:
    - name: docker pull {{ instance['image'] }}

percona_pmm_container_{{ loop.index }}_{{ i_loop.index }}:
  docker_container.running:
    - name: percona-{{ domain['name'] }}
    - user: root
    - image: {{ instance['image'] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - 0.0.0.0:443:443/tcp
    - binds:
        - /opt/pmm/{{ domain['name'] }}/{{ instance['name'] }}/etc:/etc/grafana:rw
        - /opt/acme/cert/{{ domain['name'] }}:/opt/acme/cert/{{ domain['name'] }}:rw
    - watch:
        - /opt/pmm/{{ domain['name'] }}/{{ instance['name'] }}/etc/grafana.ini

install_pmm_image_components_{{ loop.index }}_{{ i_loop.index }}:
  cmd.run:
    - name: docker exec -t percona-{{ domain['name'] }} bash -c 'yum install libXcomposite libXdamage libXtst cups libXScrnSaver pango atk adwaita-cursor-theme adwaita-icon-theme at at-spi2-atk at-spi2-core cairo-gobject colord-libs  dconf desktop-file-utils ed emacs-filesystem gdk-pixbuf2 glib-networking gnutls gsettings-desktop-schemas gtk-update-icon-cache gtk3 hicolor-icon-theme jasper-libs json-glib libappindicator-gtk3 libdbusmenu libdbusmenu-gtk3 libepoxy liberation-fonts liberation-narrow-fonts liberation-sans-fonts liberation-serif-fonts libgusb libindicator-gtk3 libmodman libproxy libsoup libwayland-cursor libwayland-egl libxkbcommon m4 mailx nettle patch psmisc redhat-lsb-core redhat-lsb-submod-security rest spax time trousers xdg-utils xkeyboard-config alsa-lib -y'

install_pmm_image_plugins{{ loop.index }}_{{ i_loop.index }}:
  cmd.run:
    - name: docker exec -t percona-{{ domain['name'] }} bash -c 'grafana-cli plugins install {{ instance['plugins'] }}'

restart_pmm_image:
  cmd.run:
    - name: docker restart percona-{{ domain['name'] }}

dump_db_cron:
  cron.present:
    - name: docker exec -i percona-{{ domain['name'] }} /bin/bash -c "pg_dump --username postgres pmm-managed" > /var/pmm_backup/pmm-managed.sql
    - user: root
    - minute: 0
    - hour: 3

dump_files_cron:
  cron.present:
    - name: docker cp percona-{{ domain['name'] }}:/srv /var/pmm_backup/ > /var/log/cron.log 2>&1
    - user: root
    - minute: 0
    - hour: 3

change_nginx_cert_1:
  cmd.run:
    - shell: /bin/bash
    - name: docker exec -i percona-{{ domain['name'] }} sed -i 's/\bssl_certificate\b\(.*\)/ssl_certificate \/opt\/acme\/cert\/{{ pillar["pmm"]["servername"] }}\/fullchain.cer;/' /etc/nginx/conf.d/pmm.conf

change_nginx_cert_2:
  cmd.run:
    - shell: /bin/bash
    - name: docker exec -i  percona-{{ domain['name'] }} sed -i 's/\bssl_certificate_key\b\(.*\)/ssl_certificate_key \/opt\/acme\/cert\/{{ pillar["pmm"]["servername"] }}\/{{ pillar["pmm"]["servername"] }}.key;/' /etc/nginx/conf.d/pmm.conf


restart container:
  cmd.run:
    - shell: /bin/bash
    - name: docker restart percona-{{ domain['name'] }}

{%- endfor %}
  {%- endfor %}

dir_for_backups:
  file.directory:
    - name: /var/pmm_backup
    - user: root
    - mode: 755
    - makedirs: True

{% endif %}
