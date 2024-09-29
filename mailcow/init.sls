{% if pillar["mailcow"] is defined %}

  {% from "acme/macros.jinja" import verify_and_issue %}

  {%- if pillar["docker-ce"] is not defined %}
    {%- set docker_ce = {"version": pillar["mailcow"]["docker-ce_version"],
                         "daemon_json": '{"iptables": true, "default-address-pools": [ {"base": "172.16.0.0/12", "size": 24} ] }'} %}
  {%- endif %}
  {%- include "docker-ce/docker-ce.sls" with context %}

postfix_stop_and_disable:
  service.dead:
    - name: postfix
      enable: False

  {% if pillar["mailcow"]["mailcow_conf"]["SKIP_LETS_ENCRYPT"] == 'y' %}
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
            log_format  main  '$remote_addr - [$time_local] "$host$request_uri" '
                              '$status $body_bytes_sent "$http_referer" '
                              '"$http_user_agent" "$proxy_add_x_forwarded_for"';
            server {
                listen 80;
                return 301 https://$host$request_uri;
            }

            server {
                listen 443 ssl;
                server_name {{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }};
                access_log /var/log/nginx/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}-access.log main;
                error_log /var/log/nginx/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}-error.log;
                ssl_certificate /opt/acme/cert/mailcow_{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/mailcow_{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}_key.key;
                location / {
                    proxy_pass http://localhost:{{ pillar["mailcow"]["mailcow_conf"]["HTTP_PORT"] }};
                    include    proxy_params;
                    proxy_set_header    X-Real-IP          $remote_addr;
                    proxy_set_header    X-Forwarded-For    $proxy_add_x_forwarded_for;
                    proxy_set_header    X-Forwarded-Host   $host;
                    proxy_set_header    X-Forwarded-Proto  $scheme;
                    proxy_headers_hash_max_size 512;
                    proxy_headers_hash_bucket_size 128;
                }
            }
        }

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

    {% if "haproxy" in pillar["mailcow"] %}
haproxy_install:
  pkg.installed:
    - pkgs:
      - haproxy

haproxy_config:
  file.managed:
    - name: /etc/haproxy/haproxy.conf
    - contents: |
        global
                log /dev/log    local0
                log /dev/log    local1 notice
                chroot /var/lib/haproxy
                stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
                stats timeout 30s
                user haproxy
                group haproxy
                daemon
                ca-base /etc/ssl/certs
                crt-base /etc/ssl/private
                ssl-default-bind-ciphers ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:RSA+AESGCM:RSA+AES:!aNULL:!MD5:!DSS
                ssl-default-bind-options no-sslv3
        defaults
                log     global
                mode    tcp
                option  tcplog
                option  dontlognull
                timeout client 1m
                timeout connect 7s
                timeout server  50000
                errorfile 400 /etc/haproxy/errors/400.http
                errorfile 403 /etc/haproxy/errors/403.http
                errorfile 408 /etc/haproxy/errors/408.http
                errorfile 500 /etc/haproxy/errors/500.http
                errorfile 502 /etc/haproxy/errors/502.http
                errorfile 503 /etc/haproxy/errors/503.http
                errorfile 504 /etc/haproxy/errors/504.http
        listen imap
                bind {{ pillar["mailcow"]["haproxy"]["EXTERNAL_IP"] }}:143
                server imap 127.0.0.1:10143 send-proxy
        listen imaps
                bind {{ pillar["mailcow"]["haproxy"]["EXTERNAL_IP"] }}:993
                server imaps 127.0.0.1:10993 send-proxy
        listen pop
                bind {{ pillar["mailcow"]["haproxy"]["EXTERNAL_IP"] }}:110
                server pop 127.0.0.1:10110 send-proxy
        listen pops
                bind {{ pillar["mailcow"]["haproxy"]["EXTERNAL_IP"] }}:995
                server pops 127.0.0.1:10995 send-proxy
        listen sieve
                bind {{ pillar["mailcow"]["haproxy"]["EXTERNAL_IP"] }}:4190
                server sieve 127.0.0.1:14190 send-proxy
        listen submission
                bind {{ pillar["mailcow"]["haproxy"]["EXTERNAL_IP"] }}:587
                server submission 127.0.0.1:10587 send-proxy
        listen smtps
                bind {{ pillar["mailcow"]["haproxy"]["EXTERNAL_IP"] }}:465
                server smtps 127.0.0.1:10465 send-proxy
    {% endif %}

    {% if "acme_account" in pillar["mailcow"] %}

      {{ verify_and_issue(pillar["mailcow"]["acme_account"], "mailcow", pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"]) }}

    {% endif %}
  {% endif %}

mailcow_clone_fom_git:
  git.cloned:
    - name: https://github.com/mailcow/mailcow-dockerized
    - target: /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}

mailcow_generate_config:
  cmd.run:
    - shell: /bin/bash
    - name: if [[ ! -e /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/mailcow.conf ]]; then /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/generate_config.sh; fi
    - cwd: /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/
    - env:
      - MAILCOW_HOSTNAME: {{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}
      - MAILCOW_TZ: {{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_TZ"] }}

  {%- for var_key, var_val in pillar["mailcow"]["mailcow_conf"].items() %}
mailcow_config_{{ var_key }}:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/mailcow.conf'
    {%- if var_key == 'MAILCOW_TZ' %}
    - pattern: '^ *TZ=.*$'
    - repl: 'TZ={{ var_val }}'
    {%- else %}
    - pattern: '^ *{{ var_key }}=.*$'
    - repl: '{{ var_key }}={{ var_val }}'
    {%- endif %}
    - append_if_not_found: True
  {%- endfor %}

mailcow_ipv6:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/docker-compose.yml'
    - pattern: '^    enable_ipv6:.*$'
    - repl: '    enable_ipv6: {{ pillar["mailcow"]["enable_ipv6"] | default(False) }}'

mailcow_data_dir:
  file.directory:
    - names:
      - /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/volumes/data
      - /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/volumes/mail_crypt
      - /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/volumes/opt/solr/server/solr/dovecot-fts/data
      - /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/volumes/sogo_web
      - /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/volumes/sogo_backup
      - /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/volumes/var/vmail_index
      - /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/volumes/var/vmail
      - /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/volumes/var/lib/rspamd
      - /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/volumes/var/lib/mysql
      - /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/volumes/var/run/mysqld
      - /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/volumes/var/spool/postfix
    - mode: 755
    - makedirs: True

mailcow_docker_compose_owerride:
  file.managed:
    - name: /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/docker-compose.override.yml
    - contents: |
    {%- if 'docker_logging' in pillar['mailcow'] %}
        services:
          unbound-mailcow:
            logging:
              driver: "{{ pillar['mailcow']['docker_logging']['driver'] }}"
              options:
      {%- for var_key, var_val in pillar["mailcow"]["docker_logging"]["options"].items() %}
                {{ var_key }}: "{{ var_val }}"
      {%- endfor %}
          mysql-mailcow:
            logging:
              driver: "{{ pillar['mailcow']['docker_logging']['driver'] }}"
              options:
      {%- for var_key, var_val in pillar["mailcow"]["docker_logging"]["options"].items() %}
                {{ var_key }}: "{{ var_val }}"
      {%- endfor %}
          redis-mailcow:
            logging:
              driver: "{{ pillar['mailcow']['docker_logging']['driver'] }}"
              options:
      {%- for var_key, var_val in pillar["mailcow"]["docker_logging"]["options"].items() %}
                {{ var_key }}: "{{ var_val }}"
      {%- endfor %}
          clamd-mailcow:
            logging:
              driver: "{{ pillar['mailcow']['docker_logging']['driver'] }}"
              options:
      {%- for var_key, var_val in pillar["mailcow"]["docker_logging"]["options"].items() %}
                {{ var_key }}: "{{ var_val }}"
      {%- endfor %}
          rspamd-mailcow:
            logging:
              driver: "{{ pillar['mailcow']['docker_logging']['driver'] }}"
              options:
      {%- for var_key, var_val in pillar["mailcow"]["docker_logging"]["options"].items() %}
                {{ var_key }}: "{{ var_val }}"
      {%- endfor %}
          php-fpm-mailcow:
            logging:
              driver: "{{ pillar['mailcow']['docker_logging']['driver'] }}"
              options:
      {%- for var_key, var_val in pillar["mailcow"]["docker_logging"]["options"].items() %}
                {{ var_key }}: "{{ var_val }}"
      {%- endfor %}
          sogo-mailcow:
            logging:
              driver: "{{ pillar['mailcow']['docker_logging']['driver'] }}"
              options:
      {%- for var_key, var_val in pillar["mailcow"]["docker_logging"]["options"].items() %}
                {{ var_key }}: "{{ var_val }}"
      {%- endfor %}
          dovecot-mailcow:
      {%- if "haproxy" in pillar["mailcow"] %}
            ports:
              - "${IMAP_PORT_HAPROXY:-127.0.0.1:10143}:10143"
              - "${IMAPS_PORT_HAPROXY:-127.0.0.1:10993}:10993"
              - "${POP_PORT_HAPROXY:-127.0.0.1:10110}:10110"
              - "${POPS_PORT_HAPROXY:-127.0.0.1:10995}:10995"
              - "${SIEVE_PORT_HAPROXY:-127.0.0.1:14190}:14190"
      {%- endif %}
            logging:
              driver: "{{ pillar['mailcow']['docker_logging']['driver'] }}"
              options:
      {%- for var_key, var_val in pillar["mailcow"]["docker_logging"]["options"].items() %}
                {{ var_key }}: "{{ var_val }}"
      {%- endfor %}
          postfix-mailcow:
      {%- if "haproxy" in pillar["mailcow"] %}
            ports:
            {#- "${SMTP_PORT_HAPROXY:-127.0.0.1:10025}:10025"#}
              - "${SMTPS_PORT_HAPROXY:-127.0.0.1:10465}:10465"
              - "${SUBMISSION_PORT_HAPROXY:-127.0.0.1:10587}:10587"
      {%- endif %}
            logging:
              driver: "{{ pillar['mailcow']['docker_logging']['driver'] }}"
              options:
      {%- for var_key, var_val in pillar["mailcow"]["docker_logging"]["options"].items() %}
                {{ var_key }}: "{{ var_val }}"
      {%- endfor %}
          memcached-mailcow:
            logging:
              driver: "{{ pillar['mailcow']['docker_logging']['driver'] }}"
              options:
      {%- for var_key, var_val in pillar["mailcow"]["docker_logging"]["options"].items() %}
                {{ var_key }}: "{{ var_val }}"
      {%- endfor %}
          nginx-mailcow:
            logging:
              driver: "{{ pillar['mailcow']['docker_logging']['driver'] }}"
              options:
      {%- for var_key, var_val in pillar["mailcow"]["docker_logging"]["options"].items() %}
                {{ var_key }}: "{{ var_val }}"
      {%- endfor %}
          acme-mailcow:
            logging:
              driver: "{{ pillar['mailcow']['docker_logging']['driver'] }}"
              options:
      {%- for var_key, var_val in pillar["mailcow"]["docker_logging"]["options"].items() %}
                {{ var_key }}: "{{ var_val }}"
      {%- endfor %}
          netfilter-mailcow:
            logging:
              driver: "{{ pillar['mailcow']['docker_logging']['driver'] }}"
              options:
      {%- for var_key, var_val in pillar["mailcow"]["docker_logging"]["options"].items() %}
                {{ var_key }}: "{{ var_val }}"
      {%- endfor %}
          watchdog-mailcow:
            logging:
              driver: "{{ pillar['mailcow']['docker_logging']['driver'] }}"
              options:
      {%- for var_key, var_val in pillar["mailcow"]["docker_logging"]["options"].items() %}
                {{ var_key }}: "{{ var_val }}"
      {%- endfor %}
          dockerapi-mailcow:
            logging:
              driver: "{{ pillar['mailcow']['docker_logging']['driver'] }}"
              options:
      {%- for var_key, var_val in pillar["mailcow"]["docker_logging"]["options"].items() %}
                {{ var_key }}: "{{ var_val }}"
      {%- endfor %}
          solr-mailcow:
            logging:
              driver: "{{ pillar['mailcow']['docker_logging']['driver'] }}"
              options:
      {%- for var_key, var_val in pillar["mailcow"]["docker_logging"]["options"].items() %}
                {{ var_key }}: "{{ var_val }}"
      {%- endfor %}
          olefy-mailcow:
            logging:
              driver: "{{ pillar['mailcow']['docker_logging']['driver'] }}"
              options:
      {%- for var_key, var_val in pillar["mailcow"]["docker_logging"]["options"].items() %}
                {{ var_key }}: "{{ var_val }}"
      {%- endfor %}
          ofelia-mailcow:
            logging:
              driver: "{{ pillar['mailcow']['docker_logging']['driver'] }}"
              options:
      {%- for var_key, var_val in pillar["mailcow"]["docker_logging"]["options"].items() %}
                {{ var_key }}: "{{ var_val }}"
      {%- endfor %}
          ipv6nat-mailcow:
      {%- if not pillar['mailcow']['enable_ipv6'] | default(false) %}
            image: bash:latest
            restart: "no"
            entrypoint: ["echo", "ipv6nat disabled in docker-compose.override.yml"]
      {%- endif %}
            logging:
              driver: "{{ pillar['mailcow']['docker_logging']['driver'] }}"
              options:
      {%- for var_key, var_val in pillar["mailcow"]["docker_logging"]["options"].items() %}
                {{ var_key }}: "{{ var_val }}"
      {%- endfor %}
    {%- elif "haproxy" in pillar["mailcow"] %}
        services:
          dovecot-mailcow:
            ports:
              - "${IMAP_PORT_HAPROXY:-127.0.0.1:10143}:10143"
              - "${IMAPS_PORT_HAPROXY:-127.0.0.1:10993}:10993"
              - "${POP_PORT_HAPROXY:-127.0.0.1:10110}:10110"
              - "${POPS_PORT_HAPROXY:-127.0.0.1:10995}:10995"
              - "${SIEVE_PORT_HAPROXY:-127.0.0.1:14190}:14190"
          postfix-mailcow:
            ports:
            {#- "${SMTP_PORT_HAPROXY:-127.0.0.1:10025}:10025"#}
              - "${SMTPS_PORT_HAPROXY:-127.0.0.1:10465}:10465"
              - "${SUBMISSION_PORT_HAPROXY:-127.0.0.1:10587}:10587"
        {%- if not pillar['mailcow']['enable_ipv6'] | default(false) %}
          ipv6nat-mailcow:
            image: bash:latest
            restart: "no"
            entrypoint: ["echo", "ipv6nat disabled in docker-compose.override.yml"]
        {%- endif %}
    {%- elif not pillar['mailcow']['enable_ipv6'] | default(false) %}
        services:
          ipv6nat-mailcow:
            image: bash:latest
            restart: "no"
            entrypoint: ["echo", "ipv6nat disabled in docker-compose.override.yml"]    
    {%- endif %}
        volumes:
          vmail-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/var/vmail'
          vmail-index-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/var/vmail_index'
          mysql-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/var/lib/mysql'
          mysql-socket-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/var/run/mysqld'
          redis-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/data/'
          rspamd-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/var/lib/rspamd'
          solr-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/opt/solr/server/solr/dovecot-fts/data'
          postfix-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/var/spool/postfix'
          crypt-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/mail_crypt'
          sogo-web-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/sogo_web'
          sogo-userdata-backup-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/sogo_backup'

  {% if not pillar['mailcow']['enable_ipv6'] | default(false) %}
unboud_ipv6_conf:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/conf/unbound/unbound.conf'
    - pattern: '^  do-ip6:.*$'
    - repl: '  do-ip6: no'

postfix_extra_cf_touch_0:
  file.touch:
    - name: /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/conf/postfix/extra.cf
postfix_ipv6_conf_1:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/conf/postfix/extra.cf'
    - pattern: '^ *inet_protocols *=.*$'
    - repl: 'inet_protocols = ipv4'
    - append_if_not_found: True
postfix_ipv6_conf_2:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/conf/postfix/extra.cf'
    - pattern: '^ *smtp_address_preference *=.*$'
    - repl: 'smtp_address_preference = ipv4'
    - append_if_not_found: True

fix_configs:
  cmd.run:
    - name: |
        sed -i '/::/d' data/conf/nginx/listen_*
        sed -i '/::/d' data/conf/nginx/templates/listen*
        sed -i '/::/d' data/conf/nginx/dynmaps.conf
        sed -i 's/,\[::\]//g' data/conf/dovecot/dovecot.conf
        sed -i 's/\[::\]://g' data/conf/phpfpm/php-fpm.d/pools.conf
    - cwd: /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}
    - shell: /bin/bash
  {% endif %}

  {% if pillar["mailcow"]["mailcow_conf"]["SKIP_LETS_ENCRYPT"] == 'y' %}
bind_ssl_certificate_for_services_in_docker:
  mount.mounted:
    - name: /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/assets/ssl/cert.pem
    - device: /opt/acme/cert/mailcow_{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}_fullchain.cer
    - mkmnt: True
    - persist: True
    - fstype: none
    - opts: bind

bind_ssl_key_for_services_in_docker:
  mount.mounted:
    - name: /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/assets/ssl/key.pem
    - device: /opt/acme/cert/mailcow_{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}_key.key
    - mkmnt: True
    - persist: True
    - fstype: none
    - opts: bind

create_script_rebind_ssl_for_services_in_docker:
  file.managed:
    - name: /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/rebind-ssl-for-services.sh
    - mode: 0744
    - contents: |
        #!/bin/bash
        umount /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/assets/ssl/cert.pem
        umount /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/assets/ssl/key.pem
        mount --bind /opt/acme/cert/mailcow_{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}_fullchain.cer /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/assets/ssl/cert.pem
        mount --bind /opt/acme/cert/mailcow_{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}_key.key /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/assets/ssl/key.pem
        docker-compose -f /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/docker-compose.yml restart
  {% else %}
mailcow_nginx_redirect.conf:
  file.managed:
    - name: /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/conf/nginx/redirect.conf
    - mode: 0644
    - contents: |
        server {
          root /web;
          listen 80 default_server;
          listen [::]:80 default_server;
          include /etc/nginx/conf.d/server_name.active;
          if ( $request_uri ~* "%0A|%0D" ) { return 403; }
          location ^~ /.well-known/acme-challenge/ {
            allow all;
            default_type "text/plain";
          }
          location / {
            return 301 https://$host$uri$is_args$args;
          }
        }
  {% endif %}

  {% if "haproxy" in pillar["mailcow"] and pillar["mailcow"]["mailcow_conf"]["SKIP_LETS_ENCRYPT"] == 'y' %}
dovecote_extra_conf_haproxy_trusted_networks:
  file.managed:
    - name: /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/conf/dovecot/extra.conf
    - mode: 0644
    - contents: |
        haproxy_trusted_networks = 172.22.1.1

haproxy_reload:
  cmd.run:
    - shell: /bin/bash
    - name: service haproxy reload
  {% endif %}

  {% if pillar["mailcow"]["rspamd"] is defined and "phishing_conf" in pillar["mailcow"]["rspamd"] %}
    {%- for var_key, var_val in pillar["mailcow"]["rspamd"]["phishing_conf"].items() %}
rspamd_phishing_conf_{{ loop.index }}:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/conf/rspamd/local.d/phishing.conf'
    - pattern: '^ *{{ var_key }}.*$'
    - repl: '{{ var_key }} = {{ var_val }};'
    - append_if_not_found: True
    {%- endfor %}
  {% endif %}
  {% if pillar["mailcow"]["rspamd"] is defined and "global_smtp_from_whitelist_map" in pillar["mailcow"]["rspamd"] %}
global_smtp_from_whitelist_map:
  file.managed:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/conf/rspamd/custom/global_smtp_from_whitelist.map'
    - contents: {{ pillar["mailcow"]["rspamd"]["global_smtp_from_whitelist_map"] | yaml_encode }}
  {% endif %}
  {% if pillar["mailcow"]["rspamd"] is defined and "global_rcpt_whitelist_map" in pillar["mailcow"]["rspamd"] %}
global_rcpt_whitelist_map:
  file.managed:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/conf/rspamd/custom/global_rcpt_whitelist.map'
    - contents: {{ pillar["mailcow"]["rspamd"]["global_rcpt_whitelist_map"] | yaml_encode }}
  {% endif %}
  {% if pillar["mailcow"]["rspamd"] is defined and "ip_wl_map" in pillar["mailcow"]["rspamd"] %}
ip_wl_map:
  file.managed:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/conf/rspamd/custom/ip_wl.map'
    - contents: {{ pillar["mailcow"]["rspamd"]["ip_wl_map"] | yaml_encode }}
  {% endif %}

  {% if pillar["mailcow"]["clamd"] is defined %}
    {% if "clamd_conf" in pillar["mailcow"]["clamd"] %}
      {%- for var_key, var_val in pillar["mailcow"]["clamd"]["clamd_conf"].items() %}
clamd_conf_{{ loop.index }}:
  file.replace:
    - name: /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/conf/clamav/clamd.conf
    - pattern: '^ *{{ var_key }}.*$'
    - repl: '{{ var_key }} {{ var_val }}'
    - append_if_not_found: True
      {%- endfor %}
    {% endif %}

    {% if "whitelist_ign2" in pillar["mailcow"]["clamd"] %}
      {%- for var_key, var_val in pillar["mailcow"]["clamd"]["whitelist_ign2"].items() %}
clamd_whitelist_ign2_{{ loop.index }}:
  file.replace:
    - name: /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/conf/clamav/whitelist.ign2
    - pattern: '^ *{{ var_key }}\.{{ var_val }}.*$'
    - repl: '{{ var_key }}.{{ var_val }}'
    - append_if_not_found: True
      {%- endfor %}
    {% endif %}
  {% endif %}

  {% if pillar["mailcow"]["postfix"] is defined and "extra_cf" in pillar["mailcow"]["postfix"] %}
postfix_extra_cf_touch:
  file.touch:
    - name: /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/conf/postfix/extra.cf
    {%- for var_key, var_val in pillar["mailcow"]["postfix"]["extra_cf"].items() %}
postfix_extra_cf_{{ loop.index }}:
  file.replace:
    - name: /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/conf/postfix/extra.cf
    - pattern: '^ *{{ var_key }}.*$'
    - repl: '{{ var_key }} = {{ var_val }}'
    - append_if_not_found: True
    {%- endfor %}
  {% endif %}

  {% if pillar["mailcow"]["postfix"] is defined and "header_checks" in pillar["mailcow"]["postfix"] %}
postfix_header_checks:
  file.managed:
    - name: /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/data/conf/postfix/header_checks
    - contents: {{ pillar["mailcow"]["postfix"]["header_checks"] | yaml_encode }}
  {% endif %}

mailcow_docker_compose_up:
  cmd.run:
    - shell: /bin/bash
    - cwd: /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}
    - name: cd /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }} && docker-compose up -d

create_cron_dovecot_full_text_serach_rescan:
  cron.present:
    - name: bash -c 'docker-compose -f /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/docker-compose.yml exec dovecot-mailcow doveadm fts rescan -A'
    - identifier: dovecot_full_text_search_rescan
    - user: root
    - minute: 30

  {% if pillar["mailcow"]["mailcow_conf"]["SKIP_LETS_ENCRYPT"] == 'y' %}
create_cron_rebind_ssl_for_services_in_docker:
  cron.present:
    - name: /opt/mailcow/{{ pillar["mailcow"]["mailcow_conf"]["MAILCOW_HOSTNAME"] }}/rebind-ssl-for-services.sh
    - identifier: rebind_ssl_certificates_for_services_in_docker
    - user: root
    - minute: 0
    - hour: 4

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
{% endif %}

