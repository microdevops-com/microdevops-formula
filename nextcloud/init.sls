{% if pillar["nextcloud"] is defined and pillar["acme"] is defined %}
{% set acme = pillar['acme'].keys() | first %}

  {%- if pillar["docker-ce"] is not defined %}
    {%- set docker_ce = {"version": pillar["nextcloud"]["docker-ce_version"],
                         "daemon_json": '{ "iptables": false, "default-address-pools": [ {"base": "172.16.0.0/12", "size": 24} ] }'} %}
  {%- endif %}
  {%- include "docker-ce/docker-ce.sls" with context %}

nginx_install:
  pkg.installed:
    - pkgs:
      - nginx

  {%- if pillar["nextcloud"]["nginx_sites_enabled"] | default(false) %}
create nginx.conf:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - contents: |
        #user www-data;
        worker_processes auto;
        worker_rlimit_nofile 40000;
        pid /run/nginx.pid;
        include /etc/nginx/modules-enabled/*.conf;
        events {
            worker_connections 8192;
        }
        http {
          sendfile on;
          tcp_nopush on;
          tcp_nodelay on;
          keepalive_timeout 65;
          types_hash_max_size 2048;
          server_names_hash_bucket_size 64;
          #include /etc/nginx/mime.types;
          default_type application/octet-stream;
          ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
          ssl_prefer_server_ciphers on;
          access_log /var/log/nginx/access.log;
          error_log /var/log/nginx/error.log;
          gzip on;
          include /etc/nginx/conf.d/*.conf;
          include /etc/nginx/sites-enabled/*;
        }
    {%- for domain in pillar["nextcloud"]["domains"] %}
create /etc/nginx/sites-available/{{ domain["name"] }}.conf:
  file.managed:
    - name: /etc/nginx/sites-available/{{ domain["name"] }}.conf
    - contents: |
        map $http_upgrade $connection_upgrade {
          default upgrade;
          ''      close;
        }
        # Set the `immutable` cache control options only for assets with a cache busting `v` argument
        map $arg_v $asset_immutable {
            "" "";
            default "immutable";
        }

        {%- if pillar["nextcloud"]["external_port"] is not defined %}
        server {
            listen 80;
            server_name {{ domain["name"] }};

            # Prevent nginx HTTP Server Detection
            server_tokens off;

            return 301 https://$host$request_uri;
        }
        {%- endif %}
        
        upstream {{ domain["name"] | replace(".","_") }} {
            server localhost:{{ domain["internal_port"] }};
        }
            
        server {
            listen 443 ssl http2;
            
            server_name {{ domain["name"] }};
            root /opt/nextcloud/{{ domain["name"] }}/data;
            ssl_certificate /opt/acme/cert/nextcloud_{{ domain["name"] }}_fullchain.cer;
            ssl_certificate_key /opt/acme/cert/nextcloud_{{ domain["name"] }}_key.key;

            fastcgi_read_timeout 300s;

            # Prevent nginx HTTP Server Detection
            server_tokens off;

            # HSTS settings
            # WARNING: Only add the preload option once you read about
            # the consequences in https://hstspreload.org/. This option
            # will add the domain to a hardcoded list that is shipped
            # in all major browsers and getting removed from this list
            # could take several months.
            add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;

            # set max upload size and increase upload timeout:
            client_max_body_size 10G;
            client_body_timeout 300s;
            fastcgi_buffers 64 4K;

            # Enable gzip but do not remove ETag headers
            gzip on;
            gzip_vary on;
            gzip_comp_level 4;
            gzip_min_length 256;
            gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
            gzip_types application/atom+xml text/javascript application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/wasm application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;

            # Pagespeed is not supported by Nextcloud, so if your server is built
            # with the `ngx_pagespeed` module, uncomment this line to disable it.
            #pagespeed off;

            # The settings allows you to optimize the HTTP2 bandwitdth.
            # See https://blog.cloudflare.com/delivering-http-2-upload-speed-improvements/
            # for tunning hints
            client_body_buffer_size 512k;

            # HTTP response headers borrowed from Nextcloud `.htaccess`
            # WARNING: Only add the preload option once you read about
            # the consequences in https://hstspreload.org/. This option
            # will add the domain to a hardcoded list that is shipped
            # in all major browsers and getting removed from this list
            # could take several months.
            add_header Referrer-Policy                   "no-referrer"       always;
            add_header X-Content-Type-Options            "nosniff"           always;
            add_header X-Download-Options                "noopen"            always;
            add_header X-Frame-Options                   "SAMEORIGIN"        always;
            add_header X-Permitted-Cross-Domain-Policies "none"              always;
            add_header X-Robots-Tag                      "noindex, nofollow" always;
            add_header X-XSS-Protection                  "1; mode=block"     always;

            # Remove X-Powered-By, which is an information leak
            fastcgi_hide_header X-Powered-By;

            # Add .mjs as a file extension for javascript
            # Either include it in the default mime.types list
            # or include you can include that list explicitly and add the file extension
            # only for Nextcloud like below:
            include mime.types;
            types {
                text/javascript js mjs;
            }

            # Specify how to handle directories -- specifying `/index.php$request_uri`
            # here as the fallback means that Nginx always exhibits the desired behaviour
            # when a client requests a path that corresponds to a directory that exists
            # on the server. In particular, if that directory contains an index.php file,
            # that file is correctly served; if it doesn't, then the request is passed to
            # the front-end controller. This consistent behaviour means that we don't need
            # to specify custom rules for certain paths (e.g. images and other assets,
            # `/updater`, `/ocs-provider`), and thus
            # `try_files $uri $uri/ /index.php$request_uri`
            # always provides the desired behaviour.
            index index.php index.html /index.php$request_uri;

            # Rule borrowed from `.htaccess` to handle Microsoft DAV clients
            location = / {
                if ( $http_user_agent ~ ^DavClnt ) {
                    return 302 /remote.php/webdav/$is_args$args;
                }
            }

            location = /robots.txt {
                allow all;
                log_not_found off;
                access_log off;
            }
            
            # The following 2 rules are only needed for the user_webfinger app.
            # Uncomment it if you're planning to use this app.
            #rewrite ^/.well-known/host-meta /public.php?service=host-meta last;
            #rewrite ^/.well-known/host-meta.json /public.php?service=host-meta-json last;
            #
            # The following rule is only needed for the Social app.
            # Uncomment it if you're planning to use this app.
            #rewrite ^/.well-known/webfinger /public.php?service=webfinger last;
            #
            # The folliwing 2 rules have been added to remove the following warnings from the status page:
            #    "Your web server is not properly set up to resolve "/.well-known/webfinger".
            #     Further information can be found in the documentation."
            #    "Your web server is not properly set up to resolve "/.well-known/nodeinfo".
            #     Further information can be found in the documentation."
            #rewrite ^/.well-known/webfinger /index.php$uri redirect;
            #rewrite ^/.well-known/nodeinfo  /index.php$uri redirect;


            # Make a regex exception for `/.well-known` so that clients can still
            # access it despite the existence of the regex rule
            # `location ~ /(\.|autotest|...)` which would otherwise handle requests
            # for `/.well-known`.
            location ^~ /.well-known {
                # The rules in this block are an adaptation of the rules
                # in `.htaccess` that concern `/.well-known`.

                location = /.well-known/carddav { return 301 /remote.php/dav/; }
                location = /.well-known/caldav  { return 301 /remote.php/dav/; }

                location /.well-known/acme-challenge    { try_files $uri $uri/ =404; }
                location /.well-known/pki-validation    { try_files $uri $uri/ =404; }

                # Let Nextcloud's API for `/.well-known` URIs handle all other
                # requests by passing them to the front-end controller.
                return 301 /index.php$request_uri;
            }

            # Rules borrowed from `.htaccess` to hide certain paths from clients
            location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:$|/)  { return 404; }
            location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console)                { return 404; }

            # Ensure this block, which passes PHP files to the PHP process, is above the blocks
            # which handle static assets (as seen below). If this block is not declared first,
            # then Nginx will encounter an infinite rewriting loop when it prepends `/index.php`
            # to the URI, resulting in a HTTP 500 error response.
    
            location ~ \.php(?:$|/) {
                # Required for legacy support
                rewrite ^/(?!index|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|ocs-provider\/.+|.+\/richdocumentscode\/proxy) /index.php$request_uri;

                fastcgi_split_path_info ^(.+?\.php)(/.*)$;
                set $path_info $fastcgi_path_info;

                try_files $fastcgi_script_name =404;

                include fastcgi_params;
                fastcgi_param SCRIPT_FILENAME /var/www/html/$fastcgi_script_name;
                fastcgi_param PATH_INFO $path_info;
                fastcgi_param HTTPS on;

                fastcgi_param modHeadersAvailable true;         # Avoid sending the security headers twice
                fastcgi_param front_controller_active true;     # Enable pretty urls
                fastcgi_pass {{ domain["name"] | replace(".","_") }};
                
                fastcgi_intercept_errors on;
                fastcgi_request_buffering off;

                fastcgi_max_temp_file_size 0;
            }

            # Serve static files
            # Adding the cache control header for js, css and map files
            # Make sure it is BELOW the PHP block
            location ~ \.(?:css|js|mjs|svg|gif|png|jpg|ico|wasm|tflite|map|html|ttf|jpeg|bcmap|mp4|webm)$ {
                try_files $uri /index.php$request_uri;
                add_header Cache-Control "public, max-age=15778463, $asset_immutable";
                access_log off;     # Optional: Don't log access to assets

                location ~ \.wasm$ {
                    default_type application/wasm;
                }
            }
            location ~ \.woff2?$ {
                try_files $uri /index.php$request_uri;
                expires 7d;         # Cache-Control policy borrowed from `.htaccess`
                access_log off;     # Optional: Don't log access to assets
            }

            # Rule borrowed from `.htaccess`
            location /remote {
                return 301 /remote.php$request_uri;
            }

            location / {
                try_files $uri $uri/ /index.php$request_uri;
            }
        }
create symlink /etc/nginx/sites-enabled/{{ domain["name"] }}.conf:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ domain["name"] }}.conf
    - target: /etc/nginx/sites-available/{{ domain["name"] }}.conf
    - force: True
    {%- endfor %}
  
  {%- else %}

nginx_files_1:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - contents: |
        worker_processes 4;
        worker_rlimit_nofile 40000;

        events {
            worker_connections 8192;
        }

        http {
            #include /etc/nginx/mime.types;
            default_type application/octet-stream;
            sendfile on;
            keepalive_timeout 65;
            map $http_upgrade $connection_upgrade {
              default upgrade;
              ''      close;
            }
            # Set the `immutable` cache control options only for assets with a cache busting `v` argument
            map $arg_v $asset_immutable {
                "" "";
                default "immutable";
            }
            server {
                listen 80;

                # Prevent nginx HTTP Server Detection
                server_tokens off;

                return 301 https://$host$request_uri;
            }
    {%- for domain in pillar["nextcloud"]["domains"] %}
            
            upstream {{ domain["name"] | replace(".","_") }} {
                server localhost:{{ domain["internal_port"] }};
            }
            
            server {
                listen 443 ssl http2;
                
                server_name {{ domain["name"] }};
                root /opt/nextcloud/{{ domain["name"] }}/data;
                ssl_certificate /opt/acme/cert/nextcloud_{{ domain["name"] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/nextcloud_{{ domain["name"] }}_key.key;

                fastcgi_read_timeout 300s;

                # Prevent nginx HTTP Server Detection
                server_tokens off;

                # HSTS settings
                # WARNING: Only add the preload option once you read about
                # the consequences in https://hstspreload.org/. This option
                # will add the domain to a hardcoded list that is shipped
                # in all major browsers and getting removed from this list
                # could take several months.
                add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;

                # set max upload size and increase upload timeout:
                client_max_body_size 10G;
                client_body_timeout 300s;
                fastcgi_buffers 64 4K;

                # Enable gzip but do not remove ETag headers
                gzip on;
                gzip_vary on;
                gzip_comp_level 4;
                gzip_min_length 256;
                gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
                gzip_types application/atom+xml text/javascript application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/wasm application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;

                # Pagespeed is not supported by Nextcloud, so if your server is built
                # with the `ngx_pagespeed` module, uncomment this line to disable it.
                #pagespeed off;

                # The settings allows you to optimize the HTTP2 bandwitdth.
                # See https://blog.cloudflare.com/delivering-http-2-upload-speed-improvements/
                # for tunning hints
                client_body_buffer_size 512k;

                # HTTP response headers borrowed from Nextcloud `.htaccess`
                # WARNING: Only add the preload option once you read about
                # the consequences in https://hstspreload.org/. This option
                # will add the domain to a hardcoded list that is shipped
                # in all major browsers and getting removed from this list
                # could take several months.
                add_header Referrer-Policy                   "no-referrer"       always;
                add_header X-Content-Type-Options            "nosniff"           always;
                add_header X-Download-Options                "noopen"            always;
                add_header X-Frame-Options                   "SAMEORIGIN"        always;
                add_header X-Permitted-Cross-Domain-Policies "none"              always;
                add_header X-Robots-Tag                      "noindex, nofollow" always;
                add_header X-XSS-Protection                  "1; mode=block"     always;

                # Remove X-Powered-By, which is an information leak
                fastcgi_hide_header X-Powered-By;

                # Add .mjs as a file extension for javascript
                # Either include it in the default mime.types list
                # or include you can include that list explicitly and add the file extension
                # only for Nextcloud like below:
                include mime.types;
                types {
                    text/javascript js mjs;
                }

                # Specify how to handle directories -- specifying `/index.php$request_uri`
                # here as the fallback means that Nginx always exhibits the desired behaviour
                # when a client requests a path that corresponds to a directory that exists
                # on the server. In particular, if that directory contains an index.php file,
                # that file is correctly served; if it doesn't, then the request is passed to
                # the front-end controller. This consistent behaviour means that we don't need
                # to specify custom rules for certain paths (e.g. images and other assets,
                # `/updater`, `/ocs-provider`), and thus
                # `try_files $uri $uri/ /index.php$request_uri`
                # always provides the desired behaviour.
                index index.php index.html /index.php$request_uri;

                # Rule borrowed from `.htaccess` to handle Microsoft DAV clients
                location = / {
                    if ( $http_user_agent ~ ^DavClnt ) {
                        return 302 /remote.php/webdav/$is_args$args;
                    }
                }

                location = /robots.txt {
                    allow all;
                    log_not_found off;
                    access_log off;
                }
                
                # The following 2 rules are only needed for the user_webfinger app.
                # Uncomment it if you're planning to use this app.
                #rewrite ^/.well-known/host-meta /public.php?service=host-meta last;
                #rewrite ^/.well-known/host-meta.json /public.php?service=host-meta-json last;
                #
                # The following rule is only needed for the Social app.
                # Uncomment it if you're planning to use this app.
                #rewrite ^/.well-known/webfinger /public.php?service=webfinger last;
                #
                # The folliwing 2 rules have been added to remove the following warnings from the status page:
                #    "Your web server is not properly set up to resolve "/.well-known/webfinger".
                #     Further information can be found in the documentation."
                #    "Your web server is not properly set up to resolve "/.well-known/nodeinfo".
                #     Further information can be found in the documentation."
                #rewrite ^/.well-known/webfinger /index.php$uri redirect;
                #rewrite ^/.well-known/nodeinfo  /index.php$uri redirect;


                # Make a regex exception for `/.well-known` so that clients can still
                # access it despite the existence of the regex rule
                # `location ~ /(\.|autotest|...)` which would otherwise handle requests
                # for `/.well-known`.
                location ^~ /.well-known {
                    # The rules in this block are an adaptation of the rules
                    # in `.htaccess` that concern `/.well-known`.

                    location = /.well-known/carddav { return 301 /remote.php/dav/; }
                    location = /.well-known/caldav  { return 301 /remote.php/dav/; }

                    location /.well-known/acme-challenge    { try_files $uri $uri/ =404; }
                    location /.well-known/pki-validation    { try_files $uri $uri/ =404; }

                    # Let Nextcloud's API for `/.well-known` URIs handle all other
                    # requests by passing them to the front-end controller.
                    return 301 /index.php$request_uri;
                }

                # Rules borrowed from `.htaccess` to hide certain paths from clients
                location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:$|/)  { return 404; }
                location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console)                { return 404; }

                # Ensure this block, which passes PHP files to the PHP process, is above the blocks
                # which handle static assets (as seen below). If this block is not declared first,
                # then Nginx will encounter an infinite rewriting loop when it prepends `/index.php`
                # to the URI, resulting in a HTTP 500 error response.
        
                location ~ \.php(?:$|/) {
                    # Required for legacy support
                    rewrite ^/(?!index|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|ocs-provider\/.+|.+\/richdocumentscode\/proxy) /index.php$request_uri;

                    fastcgi_split_path_info ^(.+?\.php)(/.*)$;
                    set $path_info $fastcgi_path_info;

                    try_files $fastcgi_script_name =404;

                    include fastcgi_params;
                    fastcgi_param SCRIPT_FILENAME /var/www/html/$fastcgi_script_name;
                    fastcgi_param PATH_INFO $path_info;
                    fastcgi_param HTTPS on;

                    fastcgi_param modHeadersAvailable true;         # Avoid sending the security headers twice
                    fastcgi_param front_controller_active true;     # Enable pretty urls
                    fastcgi_pass {{ domain["name"] | replace(".","_") }};
                    
                    fastcgi_intercept_errors on;
                    fastcgi_request_buffering off;

                    fastcgi_max_temp_file_size 0;
                }

                # Serve static files
                # Adding the cache control header for js, css and map files
                # Make sure it is BELOW the PHP block
                location ~ \.(?:css|js|mjs|svg|gif|png|jpg|ico|wasm|tflite|map|html|ttf|jpeg|bcmap|mp4|webm)$ {
                    try_files $uri /index.php$request_uri;
                    add_header Cache-Control "public, max-age=15778463, $asset_immutable";
                    access_log off;     # Optional: Don't log access to assets

                    location ~ \.wasm$ {
                        default_type application/wasm;
                    }
                }
                location ~ \.woff2?$ {
                    try_files $uri /index.php$request_uri;
                    expires 7d;         # Cache-Control policy borrowed from `.htaccess`
                    access_log off;     # Optional: Don't log access to assets
                }

                # Rule borrowed from `.htaccess`
                location /remote {
                    return 301 /remote.php$request_uri;
                }

                location / {
                    try_files $uri $uri/ /index.php$request_uri;
                }
            }
    {%- endfor %}
        }
  {%- endif%}
nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- for domain in pillar["nextcloud"]["domains"] %}
nginx_cert_{{ loop.index }}:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ acme }}/verify_and_issue.sh nextcloud {{ domain["name"] }}"

nextcloud_data_dir_{{ loop.index }}:
  file.directory:
    - name: /opt/nextcloud/{{ domain["name"] }}/data
    - mode: 755
    - makedirs: True

nextcloud_image_{{ loop.index }}:
  cmd.run:
    - name: docker pull {{ domain["image"] }}

nextcloud_container_{{ loop.index }}:
  docker_container.running:
    - name: nextcloud-{{ domain["name"] }}
    - user: root
    - image: {{ domain["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - publish:
        - 127.0.0.1:{{ domain["internal_port"] }}:9000/tcp
    - binds:
        - /opt/nextcloud/{{ domain["name"] }}/data:/var/www/html:rw
    - environment:
    {%- for var_key, var_val in domain["env_vars"].items() %}
        - {{ var_key }}: {{ var_val }}
    {%- endfor %}

nextcloud-available_{{ loop.index }}:
  cmd.run:
    - name: 'while [ $(curl -sL -u {{ domain["env_vars"]["NEXTCLOUD_ADMIN_USER"] }}:{{ domain["env_vars"]["NEXTCLOUD_ADMIN_PASSWORD"] }} https://{{ domain["name"] }}/ocs/v2.php/apps/serverinfo/api/v1/info?format=json | jq -r ".ocs.meta.statuscode") != 200 ]; do sleep 1; done'
    - timeout: 120

    {% if "php_fpm" in domain and "pm.max_children" in domain["php_fpm"] %}
nextcloud_php-fpm_set_pm.max_children_{{ loop.index }}:
  cmd.run:
    - name: docker exec nextcloud-{{ domain["name"] }} bash -c "sed -Ei  's/^ *pm\.max_children\ =.*$/pm.max_children = {{ domain["php_fpm"]["pm.max_children"] }}/g' /usr/local/etc/php-fpm.d/www.conf"
    {% endif %}

nextcloud_container_install_libmagickcore_{{ loop.index }}:
  cmd.run:
    - name: docker exec nextcloud-{{ domain["name"] }} bash -c 'apt update && apt install libmagickcore-6.q16-6-extra iproute2 -y'

nextcloud_container_install_php_bz2_{{ loop.index }}:
  cmd.run:
    - name: docker exec nextcloud-{{ domain["name"] }} bash -c 'apt update && apt install -y libbz2-dev && docker-php-ext-install bz2' && docker restart nextcloud-{{ domain["name"] }}

nextcloud_config_default_phone_region_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'sleep 10; php occ config:system:set default_phone_region --value="{{ domain["default_phone_region"] }}"'

nextcloud_config_overwrite_cli_url_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:system:set overwrite.cli.url --value="{{ domain["overwrite_cli_url"] }}"'

nextcloud_missing_indexes_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ db:add-missing-indices'

nextcloud_cron_{{ loop.index }}:
  cron.present:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} php -f /var/www/html/cron.php
    - identifier: nextcloud-cron-{{ domain["name"] }}
    - user: root
    - minute: "*/5"

nextcloud_update_all_applications_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:update --all; sleep 10'

    {%- if "onlyoffice" in domain %}
nextcloud_config_onlyoffice_0_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:disable richdocuments || true'

nextcloud_config_onlyoffice_1_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:install onlyoffice || true'

nextcloud_config_onlyoffice_1_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:enable onlyoffice --force || true'

nextcloud_config_onlyoffice_2_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:system:set onlyoffice DocumentServerUrl --value={{ domain["onlyoffice"]["DocumentServerUrl"] }}'

nextcloud_config_onlyoffice_3_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:system:set onlyoffice DocumentServerInternalUrl --value={{ domain["onlyoffice"]["DocumentServerInternalUrl"] }}'

nextcloud_config_onlyoffice_4_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:system:set onlyoffice StorageUrl --value={{ domain["onlyoffice"]["StorageUrl"] }}'

    {%- endif %}
    {%- if "collabora" in domain %}
nextcloud_config_collabora_0_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:disable onlyoffice || true'

nextcloud_config_collabora_1_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:install richdocuments || true'

nextcloud_config_collabora_2_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:enable --force richdocuments || true'

nextcloud_config_collabora_3_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:app:set richdocuments wopi_url --value {{ domain["collabora"]["DocumentServerUrl"] }}'

nextcloud_config_collabora_4_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:app:set richdocuments wopi_allowlist --value {{ domain["collabora"]["wopi_allowlist"] }}'

      {%- if "doc_format" in domain["collabora"] %}
nextcloud_config_collabora_5_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:app:set richdocuments doc_format --value {{ domain["collabora"]["doc_format"] }}'
      {%- endif %}

nextcloud_config_collabora_6_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ richdocuments:activate-config'

    {%- endif %}
    {%- if "user_saml" in domain %}

nextcloud_config_user_saml_1_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:install user_saml || true'

nextcloud_config_user_saml_2_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:enable user_saml'

nextcloud_config_user_saml_3_{{ loop.index }}:
  file.serialize:
    - name: /opt/nextcloud/{{ domain["name"] }}/data/user_saml_config.json
    - dataset:
        apps:
          user_saml: {{ domain["user_saml"] | json }}
    - formatter: json

nextcloud_config_user_saml_4_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:import < user_saml_config.json'

nextcloud_remove_config_user_saml_{{ loop.index }}:
  file.absent:
    - name: /opt/nextcloud/{{ domain["name"] }}/data/user_saml_config.json

    {%- endif %}
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
