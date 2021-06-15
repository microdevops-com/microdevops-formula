{% if pillar["xwiki"] is defined %}
docker_install_00:
  file.directory:
    - name: /etc/docker
    - mode: 700

docker_install_01:
  file.managed:
    - name: /etc/docker/daemon.json
    - contents: |
        { "iptables": false, "default-address-pools": [ {"base": "172.16.0.0/12", "size": 24} ] }

docker_install_1:
  pkgrepo.managed:
    - humanname: Docker CE Repository
    - name: deb [arch=amd64] https://download.docker.com/linux/{{ grains["os"]|lower }} {{ grains["oscodename"] }} stable
    - file: /etc/apt/sources.list.d/docker-ce.list
    - key_url: https://download.docker.com/linux/{{ grains["os"]|lower }}/gpg

docker_install_2:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs: 
        - docker-ce: '{{ pillar["xwiki"]["docker-ce_version"] }}*'
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
    - name: systemctl restart docker
    - onchanges:
        - file: /etc/docker/daemon.json

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx

nginx_files_1:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - contents: |
        worker_processes 4;
        worker_rlimit_nofile 40000;

        events {
            worker_connections 8192;
            use epoll;
            multi_accept on;
        }

        http {
            include /etc/nginx/mime.types;
            default_type application/octet-stream;
            sendfile on;
            tcp_nopush on;
            tcp_nodelay on;
            gzip on;
            gzip_comp_level 4;
            gzip_types text/plain text/css application/x-javascript text/xml application/xml application/xml+rss text/javascript;
            gzip_vary on;
            gzip_proxied any;
            client_max_body_size 1000m;
            
            server {
                listen 80;
                return 301 https://$host$request_uri;
            }
  {%- for domain in pillar["xwiki"]["domains"] %}

            server {
                listen 443 ssl;
                server_name {{ domain["name"] }};
                ssl_certificate /opt/acme/cert/xwiki_{{ domain["name"] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/xwiki_{{ domain["name"] }}_key.key;

                location / {
                    proxy_pass http://localhost:{{ domain["internal_port"] }}/;
                    include    proxy_params;
                    add_header Content-Security-Policy upgrade-insecure-requests;
                }
            }
  {%- endfor %}
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- for domain in pillar["xwiki"]["domains"] %}
nginx_cert_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "openssl verify -CAfile /opt/acme/cert/xwiki_{{ domain["name"] }}_ca.cer /opt/acme/cert/xwiki_{{ domain["name"] }}_fullchain.cer 2>&1 | grep -q -i -e error -e cannot; [ ${PIPESTATUS[1]} -eq 0 ] && /opt/acme/home/acme_local.sh --cert-file /opt/acme/cert/xwiki_{{ domain["name"] }}_cert.cer --key-file /opt/acme/cert/xwiki_{{ domain["name"] }}_key.key --ca-file /opt/acme/cert/xwiki_{{ domain["name"] }}_ca.cer --fullchain-file /opt/acme/cert/xwiki_{{ domain["name"] }}_fullchain.cer --issue -d {{ domain["name"] }} || true"

xwiki_data_dir_{{ loop.index }}:
  file.directory:
    - name: /opt/xwiki/{{ domain["name"] }}/data
    - mode: 755
    - makedirs: True

xwiki_image_{{ loop.index }}:
  cmd.run:
    - name: docker pull {{ domain["image"] }}

xwiki_container_{{ loop.index }}:
  docker_container.running:
    - name: xwiki-{{ domain["name"] }}
    - user: root
    - image: {{ domain["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - 127.0.0.1:{{ domain["internal_port"] }}:8080/tcp
    - binds:
        - /opt/xwiki/{{ domain["name"] }}/data:/usr/local/xwiki/data:rw
    {%- if "env_vars" in domain %}
    - environment:
      {%- for var_key, var_val in domain["env_vars"].items() %}
        - {{ var_key }}: {{ var_val }}
      {%- endfor %}
    {%- endif %}

wait_for_container_{{ loop.index }}:
  cmd.run:
    - name: sleep {{ domain["container_start_timeout"] }}

xwiki_validationkey_{{ loop.index }}:
  file.replace:
    - name: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.cfg'
    - pattern: '^ *xwiki.authentication.validationKey=.*$'
    - repl: 'xwiki.authentication.validationKey={{ domain["validationkey"] }}'
    - append_if_not_found: True

xwiki_encryptionkey_{{ loop.index }}:
  file.replace:
    - name: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.cfg'
    - pattern: '^ *xwiki.authentication.encryptionKey=.*$'
    - repl: 'xwiki.authentication.encryptionKey={{ domain["encryptionkey"] }}'
    - append_if_not_found: True

  {%- if "oidc" in domain %}

xwiki_authentication_authclass_{{ loop.index }}:
  file.replace:
    - name: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.cfg'
    - pattern: '^ *xwiki.authentication.authclass=.*$'
    - repl: 'xwiki.authentication.authclass={{ domain["oidc"]["xwiki.authentication.authclass"] }}'
    - append_if_not_found: True

xwiki_oidc_xwikiprovider_{{ loop.index }}:
  file.replace:
    - name: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.properties'
    - pattern: '^ *oidc.xwikiprovider=.*$'
    - repl: 'oidc.xwikiprovider={{ domain["oidc"]["oidc.xwikiprovider"] }}'
    - append_if_not_found: True

xwiki_oidc_endpoint_authorization_{{ loop.index }}:
  file.replace:
    - name: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.properties'
    - pattern: '^ *oidc.endpoint.authorization=.*$'
    - repl: 'oidc.endpoint.authorization={{ domain["oidc"]["oidc.endpoint.authorization"] }}'
    - append_if_not_found: True

xwiki_oidc_endpoint_token_{{ loop.index }}:
  file.replace:
    - name: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.properties'
    - pattern: '^ *oidc.endpoint.token=.*$'
    - repl: 'oidc.endpoint.token={{ domain["oidc"]["oidc.endpoint.token"] }}'
    - append_if_not_found: True

xwiki_oidc_endpoint_userinfo_{{ loop.index }}:
  file.replace:
    - name: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.properties'
    - pattern: '^ *oidc_endpoint_userinfo=.*$'
    - repl: 'oidc.endpoint.userinfo={{ domain["oidc"]["oidc.endpoint.userinfo"] }}'
    - append_if_not_found: True

xwiki_oidc_scope_{{ loop.index }}:
  file.replace:
    - name: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.properties'
    - pattern: '^ *oidc.scope=.*$'
    - repl: 'oidc.scope={{ domain["oidc"]["oidc.scope"] }}'
    - append_if_not_found: True

xwiki_oidc_endpoint_userinfo_method_{{ loop.index }}:
  file.replace:
    - name: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.properties'
    - pattern: '^ *oidc.endpoint.userinfo.method=.*$'
    - repl: 'oidc.endpoint.userinfo.method={{ domain["oidc"]["oidc.endpoint.userinfo.method"] }}'
    - append_if_not_found: True

xwiki_oidc_user_nameFormater_{{ loop.index }}:
  file.replace:
    - name: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.properties'
    - pattern: '^ *oidc.user.nameFormater=.*$'
    - repl: 'oidc_user_nameFormater={{ domain["oidc"]["oidc.user.nameFormater"] }}'
    - append_if_not_found: True

xwiki_oidc_user_subjectFormater_{{ loop.index }}:
  file.replace:
    - name: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.properties'
    - pattern: '^ *oidc.user.subjectFormater=.*$'
    - repl: 'oidc.user.subjectFormater={{ domain["oidc"]["oidc.user.subjectFormater"] }}'
    - append_if_not_found: True

xwiki_oidc_groups_claim_{{ loop.index }}:
  file.replace:
    - name: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.properties'
    - pattern: '^ *oidc.groups.claim=.*$'
    - repl: 'oidc.groups.claim={{ domain["oidc"]["oidc.groups.claim"] }}'
    - append_if_not_found: True

xwiki_oidc_userinfoclaims_{{ loop.index }}:
  file.replace:
    - name: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.properties'
    - pattern: '^ *oidc.userinfoclaims=.*$'
    - repl: 'oidc.userinfoclaims={{ domain["oidc"]["oidc.userinfoclaims"] }}'
    - append_if_not_found: True

xwiki_oidc_clientid_{{ loop.index }}:
  file.replace:
    - name: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.properties'
    - pattern: '^ *oidc.clientid=.*$'
    - repl: 'oidc.clientid={{ domain["oidc"]["oidc.clientid"] }}'
    - append_if_not_found: True

xwiki_oidc_secret_{{ loop.index }}:
  file.replace:
    - name: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.properties'
    - pattern: '^ *oidc.secret=.*$'
    - repl: 'oidc.secret={{ domain["oidc"]["oidc.secret"] }}'
    - append_if_not_found: True

xwiki_oidc_endpoint_token_auth_method_{{ loop.index }}:
  file.replace:
    - name: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.properties'
    - pattern: '^ *oidc.endpoint.token.auth_method=.*$'
    - repl: 'oidc.endpoint.token.auth_method={{ domain["oidc"]["oidc.endpoint.token.auth_method"] }}'
    - append_if_not_found: True

xwiki_oidc_skipped_{{ loop.index }}:
  file.replace:
    - name: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.properties'
    - pattern: '^ *oidc.skipped=.*$'
    - repl: 'oidc.skipped={{ domain["oidc"]["oidc.skipped"] }}'
    - append_if_not_found: True

  {%- endif %}

xwiki_tomcat_https_proxy_fix_{{ loop.index }}:
  cmd.run:
    - name: docker exec -i xwiki-{{ domain["name"] }} bash -c 'sed -ie "s/<Connector port=\"8080\" protocol=\"HTTP\/1.1\" *$/<Connector port=\"8080\" protocol=\"HTTP\/1.1\" scheme=\"https\"/g" /usr/local/tomcat/conf/server.xml'

xwiki_container_restart_{{ loop.index }}:
  cmd.run:
    - name: docker stop xwiki-{{ domain["name"] }} && docker start xwiki-{{ domain["name"] }}
    - onchanges:
        - file: '/opt/xwiki/{{ domain["name"] }}/data/xwiki.cfg'

  {%- endfor %}

nginx_reload:
  cmd.run:
    - runas: root
    - name: service nginx configtest && service nginx reload

nginx_reload_cron:
  cron.present:
    - name: /usr/sbin/service nginx configtest && /usr/sbin/service nginx reload
    - identifier: nginx_reload
    - user: root
    - minute: 15
    - hour: 6

{% endif %}
