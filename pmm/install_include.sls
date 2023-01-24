grafana_dirs:
  file.directory:
    - names:
      - /opt/pmm/{{ pillar["pmm"]["name"] }}{{ pillar["pmm"]["gf_path_provisioning"] }}/dashboards
      - /opt/pmm/{{ pillar["pmm"]["name"] }}{{ pillar["pmm"]["gf_path_provisioning"] }}/datasources
      - /opt/pmm/{{ pillar["pmm"]["name"] }}{{ pillar["pmm"]["gf_path_provisioning"] }}/notifiers
      - /opt/pmm/{{ pillar["pmm"]["name"] }}{{ pillar["pmm"]["gf_path_provisioning"] }}/plugins
      - /opt/pmm/{{ pillar["pmm"]["name"] }}{{ pillar["pmm"]["gf_path_var_lib"] }}
    - mode: 755
    - makedirs: True
{#
docker_network_add:
  docker_network.present:
    - name: grafana-image-renderer

grafana_image_renderer_container:
  docker_container.running:
    - name: renderer
    - user: root
    - image:  grafana/grafana-image-renderer:3.5.0
    - detach: True
    - restart_policy: unless-stopped
    - networks:
        - grafana-image-renderer
#}
pmm_server_container:
  docker_container.running:
    - name: percona-{{ pillar["pmm"]["name"] }}
    - user: root
    - image: {{ pillar["pmm"]["image"] }}
    - detach: True
    - restart_policy: unless-stopped
{#    - networks:
        - grafana-image-renderer	#}
    - publish:
        - 0.0.0.0:443:443/tcp
    - binds:
        - /opt/pmm/{{ pillar["pmm"]["name"] }}/etc/grafana:/etc/grafana:rw
        - /opt/acme/cert/{{ pillar["pmm"]["name"] }}:/opt/acme/cert/{{ pillar["pmm"]["name"] }}:rw
        - /opt/pmm/{{ pillar["pmm"]["name"] }}{{ pillar["pmm"]["gf_path_var_lib"] }}:{{ pillar["pmm"]["gf_path_var_lib"] }}:rw
    - watch:
        - /opt/pmm/{{ pillar["pmm"]["name"] }}/etc/grafana/grafana.ini
    - volumes_from: percona-{{ pillar["pmm"]["name"] }}-data
    {%- if "env_vars" in pillar["pmm"] %}
    - environment:
      {%- for var_key, var_val in pillar["pmm"]["env_vars"].items() %}
        - {{ var_key }}: {{ var_val }}
      {%- endfor %}
    {%- endif %}

acme_cert:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["pmm"]["acme_account"] }}/verify_and_issue.sh percona_pmm {{ pillar["pmm"]["name"] }}"
    
change_nginx_cert:
  cmd.run:
    - shell: /bin/bash
    - name: docker exec -i percona-{{ pillar["pmm"]["name"] }} sed -i 's/\bssl_certificate\b\(.*\)/ssl_certificate \/opt\/acme\/cert\/{{ pillar["pmm"]["name"] }}\/fullchain.cer;/' /etc/nginx/conf.d/pmm.conf

change_nginx_key:
  cmd.run:
    - shell: /bin/bash
    - name: docker exec -i  percona-{{ pillar["pmm"]["name"] }} sed -i 's/\bssl_certificate_key\b\(.*\)/ssl_certificate_key \/opt\/acme\/cert\/{{ pillar["pmm"]["name"] }}\/{{ pillar["pmm"]["name"] }}.key;/' /etc/nginx/conf.d/pmm.conf

restart nginx:
  cmd.run:
    - shell: /bin/bash
    - name: docker exec -t percona-{{ pillar["pmm"]["name"] }} supervisorctl restart nginx

install_grafana_image_renderer_components:
  cmd.run:
    - name: docker exec -t percona-{{ pillar["pmm"]["name"] }} bash -c 'yum install libXcomposite libXdamage libXtst cups libXScrnSaver pango atk adwaita-cursor-theme adwaita-icon-theme at at-spi2-atk at-spi2-core cairo-gobject colord-libs  dconf desktop-file-utils ed emacs-filesystem gdk-pixbuf2 glib-networking gnutls gsettings-desktop-schemas gtk-update-icon-cache gtk3 hicolor-icon-theme jasper-libs json-glib libappindicator-gtk3 libdbusmenu libdbusmenu-gtk3 libepoxy liberation-fonts liberation-narrow-fonts liberation-sans-fonts liberation-serif-fonts libgusb libindicator-gtk3 libmodman libproxy libsoup libwayland-cursor libwayland-egl libxkbcommon m4 mailx nettle patch psmisc redhat-lsb-core redhat-lsb-submod-security rest spax time trousers xdg-utils xkeyboard-config alsa-lib -y'

pmm-data_backup_script:
  file.managed:
    - name: /opt/pmm/{{ pillar["pmm"]["name"] }}/backup_pmm-data.sh
    - contents: |
        #!/bin/bash
        mkdir -p /opt/pmm/{{ pillar["pmm"]["name"] }}/backup
        iptables -A ufw-before-forward -d $(dig +short api.telegram.org) -j REJECT --reject-with icmp-port-unreachable
        docker stop percona-{{ pillar["pmm"]["name"] }}
        tar --exclude='/opt/pmm/{{ pillar["pmm"]["name"] }}/backup' -cf /opt/pmm/{{ pillar["pmm"]["name"] }}/backup/percona-{{ pillar["pmm"]["name"] }}-data_opt.tar /opt/pmm/{{ pillar["pmm"]["name"] }}
        docker run --rm --volumes-from percona-{{ pillar["pmm"]["name"] }}-data -v /opt/pmm/{{ pillar["pmm"]["name"] }}/backup:/backup ubuntu tar cf /backup/percona-{{ pillar["pmm"]["name"] }}-data_srv.tar /srv
        docker start percona-{{ pillar["pmm"]["name"] }}
        #echo "CONTAINER percona-{{ pillar["pmm"]["name"] }} STARTED"
        #echo "Started timeout to disable firewall for api.telegram.org"
        sleep 180
        iptables -D ufw-before-forward -d $(dig +short api.telegram.org) -j REJECT --reject-with icmp-port-unreachable
    - mode: 774

pmm-data_restore_script:
  file.managed:
    - name: /opt/pmm/{{ pillar["pmm"]["name"] }}/restore_pmm-data.sh
    - contents: |
        #!/bin/bash
        iptables -A ufw-before-forward -d $(dig +short api.telegram.org) -j REJECT --reject-with icmp-port-unreachable
        docker stop percona-{{ pillar["pmm"]["name"] }}
        cd / && tar xf /opt/pmm/{{ pillar["pmm"]["name"] }}/backup/percona-{{ pillar["pmm"]["name"] }}-data_opt.tar
        docker run --rm --volumes-from percona-{{ pillar["pmm"]["name"] }}-data -v /opt/pmm/{{ pillar["pmm"]["name"] }}/backup:/backup ubuntu bash -c "cd / && tar xf /backup/percona-{{ pillar["pmm"]["name"] }}-data_srv.tar"
        docker start percona-{{ pillar["pmm"]["name"] }}
        #echo "CONTAINER percona-{{ pillar["pmm"]["name"] }} STARTED"
        #echo "Started timeout to disable firewall for api.telegram.org"
        sleep 180
        iptables -D ufw-before-forward -d $(dig +short api.telegram.org) -j REJECT --reject-with icmp-port-unreachable
    - mode: 774

pmm_nginx_reload_cron:
  cron.present:
    - name: docker exec percona-{{ pillar["pmm"]["name"] }} nginx -s reload
    - identifier: pmm_nginx_reload
    - user: root
    - minute: 10
    - hour: 12
