{% if pillar["nextcloud"] is defined and pillar["acme"] is defined %}

  {% from "acme/macros.jinja" import verify_and_issue %}
  {%- if pillar["docker-ce"] is not defined and pillar["nextcloud"]["docker-ce_version"] is defined %}
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
          ssl_protocols TLSv1.2 TLSv1.3;
          ssl_prefer_server_ciphers on;
          access_log /var/log/nginx/access.log;
          error_log /var/log/nginx/error.log;
          gzip on;
          map $arg_v $asset_immutable {
              "" "";
              default "immutable";
          }
          include /etc/nginx/conf.d/*.conf;
          include /etc/nginx/sites-enabled/*;
        }
    {%- for domain in pillar["nextcloud"]["domains"] %}
create /etc/nginx/sites-available/{{ domain["name"] }}.conf:
  file.managed:
    - name: /etc/nginx/sites-available/{{ domain["name"] }}.conf
    - contents: |
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
                text/javascript mjs;
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
            # Without this, composer.json matches no deny rule and no static-asset rule, so
            # location / serves the real file and leaks exact dependency versions.
            location ~ ^/(?:composer\.(?:json|lock)|package(?:-lock)?\.json|core/shipped\.json)$ { return 404; }

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
    {%- if domain.get('nginx_forwards') %}
      {%- for fwd_domain in domain['nginx_forwards'] %}
create /etc/nginx/sites-available/{{ fwd_domain }}.conf:
  file.managed:
    - name: /etc/nginx/sites-available/{{ fwd_domain }}.conf
    - contents: |
        server {
            listen 80;
            server_name {{ fwd_domain }};
            return 301 https://{{ domain["name"] }}$request_uri;
        }
        server {
            listen 443 ssl http2;
            server_name {{ fwd_domain }};
            ssl_certificate /opt/acme/cert/nextcloud_{{ fwd_domain }}_fullchain.cer;
            ssl_certificate_key /opt/acme/cert/nextcloud_{{ fwd_domain }}_key.key;
            return 301 https://{{ domain["name"] }}$request_uri;
        }
create symlink /etc/nginx/sites-enabled/{{ fwd_domain }}.conf:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ fwd_domain }}.conf
    - target: /etc/nginx/sites-available/{{ fwd_domain }}.conf
    - force: True
      {%- endfor %}
    {%- endif %}
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
            ssl_protocols TLSv1.2 TLSv1.3;
            ssl_prefer_server_ciphers on;
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
                    text/javascript mjs;
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
                # Without this, composer.json matches no deny rule and no static-asset rule,
                # so location / serves the real file and leaks exact dependency versions.
                location ~ ^/(?:composer\.(?:json|lock)|package(?:-lock)?\.json|core/shipped\.json)$ { return 404; }

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
            {%- if domain.get('nginx_forwards') %}
              {%- for fwd_domain in domain['nginx_forwards'] %}
            server {
                listen 80;
                server_name {{ fwd_domain }};
                return 301 https://{{ domain["name"] }}$request_uri;
            }
            server {
                listen 443 ssl http2;
                server_name {{ fwd_domain }};
                ssl_certificate /opt/acme/cert/nextcloud_{{ fwd_domain }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/nextcloud_{{ fwd_domain }}_key.key;
                return 301 https://{{ domain["name"] }}$request_uri;
            }
              {%- endfor %}
            {%- endif %}
    {%- endfor %}
        }
  {%- endif%}
nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {%- for domain in pillar["nextcloud"]["domains"] %}
    {%- if domain.get('acme_configs') %}
      {%- for acme_cfg in domain['acme_configs'] %}
        {% for acme_domain in acme_cfg["domains"] %}
          {{ verify_and_issue(acme_cfg["name"], "nextcloud", acme_domain) }}
        {%- endfor %}
      {%- endfor %}
    {%- else %}
        {% set acme = pillar['acme'].keys() | first %}
        {{ verify_and_issue(acme, "nextcloud", domain["name"]) }}
    {%- endif %}

nextcloud_data_dir_{{ loop.index }}:
  file.directory:
    - name: /opt/nextcloud/{{ domain["name"] }}/data
    - mode: 755
    - makedirs: True

{#- A tag whose first character is not a digit floats across majors (fpm, latest,
    production-fpm). "32-fpm" floats too, but only within the 32 line - which is what you
    want for security patches and is what Nextcloud supports. Only cross-major drift is
    dangerous, so warn here and fail on the actual jump below rather than refusing to
    render, which would take nginx and the certificates down with it. #}
    {%- set _ref = domain["image"].rsplit("/", 1)[-1] %}
    {%- set _tag = _ref.rsplit(":", 1)[1] if ":" in _ref else "latest" %}
    {%- if "@" not in _ref and not _tag[:1].isdigit() %}
nextcloud_floating_image_tag_{{ loop.index }}:
  test.show_notification:
    - text: >-
        WARNING: {{ domain["name"] }} uses the floating image tag "{{ domain["image"] }}".
        Every apply pulls whatever that tag points at today, and Nextcloud refuses upgrades
        that skip a major version, so a minion that has not applied in a while can be
        re-created onto an image it cannot boot. Pin a major line in the pillar
        (e.g. nextcloud:32-fpm) and step up one major at a time.
    {%- endif %}

nextcloud_image_{{ loop.index }}:
  cmd.run:
    - name: docker pull {{ domain["image"] }}

{#- docker_container.running re-creates the container as soon as the image ID changes, so
    without this a stale minion that pulls a much newer image gets an instance Nextcloud
    refuses to upgrade ("Updates between multiple major versions and downgrades are
    unsupported"). The installed major comes from version.php through the bind mount, so it
    is readable even while the container is down; the image major comes from the image's own
    NEXTCLOUD_VERSION env, so nothing has to run. Failing here leaves the old container
    running and serving. Note test=true cannot see any of this: the pull is skipped, so this
    check is skipped, and docker_container.running then compares against the stale local
    image and reports no change. #}
nextcloud_upgrade_path_check_{{ loop.index }}:
  cmd.run:
    - name: |
        set -eu
        ver_file=/opt/nextcloud/{{ domain["name"] }}/data/version.php
        [ -f "$ver_file" ] || { echo "no version.php yet - first install, nothing to check"; exit 0; }
        cur=$(sed -n 's/.*OC_VersionString[^0-9]*\([0-9][0-9]*\).*/\1/p' "$ver_file" | head -1)
        new=$(docker image inspect {{ domain["image"] }} \
              | jq -r '.[0].Config.Env[]' \
              | sed -n 's/^NEXTCLOUD_VERSION=\([0-9][0-9]*\)\..*/\1/p' | head -1)
        [ -n "$cur" ] && [ -n "$new" ] \
          || { echo "could not read installed ($cur) / image ($new) major - refusing to guess"; exit 1; }
        echo "installed major: $cur, image major: $new"
        [ "$new" -ge "$cur" ] \
          || { echo "REFUSING: image is NC $new but NC $cur is installed - downgrades are unsupported."; exit 1; }
        [ "$new" -le "$((cur + 1))" ] \
          || { echo "REFUSING: {{ domain["image"] }} would jump NC $cur -> $new. Pin nextcloud:$((cur + 1))-fpm, apply, then step up one major at a time."; exit 1; }
    - require:
      - cmd: nextcloud_image_{{ loop.index }}

nextcloud_container_{{ loop.index }}:
  docker_container.running:
    - name: nextcloud-{{ domain["name"] }}
    - require:
      - cmd: nextcloud_upgrade_path_check_{{ loop.index }}
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

{#- Readiness is read from occ, not from the public URL: nginx_reload runs last, so on a
    first apply the vhost exists but is not loaded yet and an HTTP probe can never succeed.
    occ also reports the things that actually define "ready" - a live HTTP 200 does not
    tell you the instance is out of maintenance mode or has no pending DB upgrade. #}
    {%- set ready_timeout = domain.get("ready_timeout", 600) %}
nextcloud-available_{{ loop.index }}:
  cmd.run:
    - name: |
        set -u
        c=nextcloud-{{ domain["name"] }}
        deadline=$(( $(date +%s) + {{ ready_timeout }} ))
        while :; do
          st=$(docker exec --user www-data "$c" php occ status --output=json 2>/dev/null || true)
          {#- No `// default` here: jq's // substitutes on ANY falsy value, false included,
              so `.maintenance // true` would yield true exactly when maintenance is false -
              the check could never pass. Bare .key is also what we want for a missing key:
              jq -r prints "null", which matches neither "true" nor "false", so anything
              unexpected reads as not-ready and we keep waiting instead of racing ahead.
              jq's stderr is dropped because occ prints non-JSON while the container is
              still starting up. #}
          if [ -n "$st" ] \
             && [ "$(printf '%s' "$st" | jq -r '.installed'      2>/dev/null)" = "true"  ] \
             && [ "$(printf '%s' "$st" | jq -r '.maintenance'    2>/dev/null)" = "false" ] \
             && [ "$(printf '%s' "$st" | jq -r '.needsDbUpgrade' 2>/dev/null)" = "false" ]; then
            echo "$c ready: Nextcloud $(printf '%s' "$st" | jq -r '.versionstring' 2>/dev/null)"
            exit 0
          fi
          [ "$(date +%s)" -lt "$deadline" ] \
            || { echo "timed out after {{ ready_timeout }}s; last occ status: ${st:-<none>}"; exit 1; }
          sleep 2
        done
    - timeout: {{ ready_timeout + 60 }}
    - require:
      - docker_container: nextcloud_container_{{ loop.index }}

{#- The serverinfo token used to be the admin password, passed on the docker exec command
    line and in a curl header - for cmd.run the state name IS the script, so it landed in
    the job return and the master job cache. It is now opt-in and fed through a file.
    Leaving it unset does not clear anything: config:app:set writes to the DB, so an
    already-configured token keeps working. #}
    {%- if domain.get("serverinfo_token") %}
nextcloud_serverinfo_token_file_{{ loop.index }}:
  file.managed:
    - name: /opt/nextcloud/{{ domain["name"] }}/data/.salt_serverinfo_token
    - contents_pillar: nextcloud:domains:{{ loop.index0 }}:serverinfo_token
    {#- Read by `docker exec --user www-data` through the bind mount, so it must be owned
        by www-data (uid 33, same on host and in the image) or 0600 would lock it out. #}
    - user: www-data
    - mode: '0600'
    - show_changes: False

nextcloud_serverinfo_token_{{ loop.index }}:
  cmd.run:
    - name: >-
        docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c
        'php occ --no-warnings config:app:set serverinfo token --value "$(cat /var/www/html/.salt_serverinfo_token)"'
    - require:
      - file: nextcloud_serverinfo_token_file_{{ loop.index }}
      - cmd: nextcloud-available_{{ loop.index }}

nextcloud_serverinfo_token_cleanup_{{ loop.index }}:
  file.absent:
    - name: /opt/nextcloud/{{ domain["name"] }}/data/.salt_serverinfo_token
    - require:
      - cmd: nextcloud_serverinfo_token_{{ loop.index }}
    {%- endif %}

{#- The three states below write into the container's writable layer, which is wiped
    whenever the image changes and docker_container.running re-creates the container.
    Their unless: probes therefore ask the container itself - a marker on the host (or in
    the bind-mounted data dir) would survive a re-create that the package did not, and the
    state would then be skipped forever. #}
    {% if "php_fpm" in domain and "pm.max_children" in domain["php_fpm"] %}
nextcloud_php-fpm_set_pm.max_children_{{ loop.index }}:
  cmd.run:
    - name: docker exec nextcloud-{{ domain["name"] }} bash -c "sed -Ei  's/^ *pm\.max_children\ =.*$/pm.max_children = {{ domain["php_fpm"]["pm.max_children"] }}/g' /usr/local/etc/php-fpm.d/www.conf"
    - unless: >-
        docker exec nextcloud-{{ domain["name"] }}
        grep -qxF 'pm.max_children = {{ domain["php_fpm"]["pm.max_children"] }}' /usr/local/etc/php-fpm.d/www.conf
    - require:
      - cmd: nextcloud-available_{{ loop.index }}
    {% endif %}

{#- Re-applies the customizations that live in the container's writable layer and are wiped
    every time the image changes. Deliberately unguarded: apt is idempotent and converges,
    so running it always is self-healing and can never silently skip. Any unless: here would
    have to probe proxies (is `ip` present? is bz2 loaded?) rather than the thing being
    installed - and the day an image ships those itself, the probe passes on its own and the
    rest silently never installs. Cost of running it always: one apt-get update (~10 MB) and
    a bz2 rebuild per apply, plus the restart below firing every time. The old code did the
    same and restarted twice per apply, so this is still strictly cheaper.
      - The ImageMagick -extra package name is derived, not hardcoded. Images from NC 32 on
        are trixie-based and already ship libmagickcore-7.q16-10-extra, so there it resolves
        to a no-op - but bookworm images are still in use, and there the name is
        libmagickcore-6.q16-6-extra. The old hardcoded bookworm literal made apt exit 100 on
        trixie and install nothing at all, not even iproute2.
      - iproute2 is kept for debugging (docker exec ... ip a).
      - bz2 really is absent from the image's docker-php-ext-install list (bcmath exif ftp
        gd gmp intl ldap pcntl pdo_mysql pdo_pgsql sysvsem zip); the image's "bzip2" is only
        the CLI tool. libbz2-dev is needed just to build the extension - the built .so links
        against libbz2-1.0, which bzip2 already pulls in. #}
nextcloud_container_prepare_{{ loop.index }}:
  cmd.run:
    - name: |
        docker exec -i -e DEBIAN_FRONTEND=noninteractive nextcloud-{{ domain["name"] }} bash -s <<'NCEOF'
        set -eu
        apt-get update
        # bookworm -> libmagickcore-6.q16-6, trixie -> libmagickcore-7.q16-10
        core=$(dpkg-query -W -f='${Package}\n' 'libmagickcore-*' 2>/dev/null \
               | grep -E '^libmagickcore-[0-9]+\.q16(hdri)?-[0-9]+$' | head -n1)
        apt-get install -y --no-install-recommends iproute2 libbz2-dev ${core:+${core}-extra}
        docker-php-ext-install bz2
        NCEOF
    - require:
      - cmd: nextcloud-available_{{ loop.index }}

nextcloud_container_restart_{{ loop.index }}:
  cmd.run:
    - name: docker restart nextcloud-{{ domain["name"] }}
    - onchanges:
      - cmd: nextcloud_container_prepare_{{ loop.index }}
    {%- if "php_fpm" in domain and "pm.max_children" in domain["php_fpm"] %}
      - cmd: nextcloud_php-fpm_set_pm.max_children_{{ loop.index }}
    {%- endif %}

nextcloud_config_default_phone_region_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'sleep 10; php occ config:system:set default_phone_region --value="{{ domain["default_phone_region"] }}"'
    - require:
      - cmd: nextcloud-available_{{ loop.index }}

nextcloud_config_overwrite_cli_url_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:system:set overwrite.cli.url --value="{{ domain["overwrite_cli_url"] }}"'
    - require:
      - cmd: nextcloud-available_{{ loop.index }}

{#- Post-upgrade work: state lives in the external DB, not in the container, so unlike the
    container states above a marker on the host is the correct lifetime here. It sits in
    /opt/nextcloud/<domain>/ - the PARENT of the bind mount - so it is not under nginx's
    root and not reachable over HTTP. The `test -n "$v" &&` is load-bearing: without it a
    failing occ yields "" = "" -> true -> the repair is silently skipped forever. #}
nextcloud_db_repair_{{ loop.index }}:
  cmd.run:
    - name: |
        set -e
        docker exec --user www-data nextcloud-{{ domain["name"] }} php occ db:add-missing-indices
        docker exec --user www-data nextcloud-{{ domain["name"] }} php occ maintenance:repair --include-expensive
        docker exec --user www-data nextcloud-{{ domain["name"] }} php occ status --output=json \
          | jq -r .versionstring > /opt/nextcloud/{{ domain["name"] }}/.salt_repaired_version
    - unless: >-
        v=$(docker exec --user www-data nextcloud-{{ domain["name"] }} php occ status --output=json 2>/dev/null | jq -r '.versionstring // empty');
        test -n "$v" && test "$v" = "$(cat /opt/nextcloud/{{ domain["name"] }}/.salt_repaired_version 2>/dev/null)"
    - require:
      - cmd: nextcloud-available_{{ loop.index }}

nextcloud_cron_{{ loop.index }}:
  cron.present:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} php -f /var/www/html/cron.php
    - identifier: nextcloud-cron-{{ domain["name"] }}
    - user: root
    - minute: "*/5"

{#- The old form ended in "; sleep 10", so the exit code was sleep's and every app:update
    failure was reported as success. Dropping it means real failures now surface. #}
    {%- if domain.get("update_apps", True) %}
nextcloud_update_all_applications_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} php occ --no-warnings app:update --all
    - require:
      - cmd: nextcloud-available_{{ loop.index }}
    {%- endif %}

    {%- if "onlyoffice" in domain %}
nextcloud_config_onlyoffice_0_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:disable richdocuments || true'
    - require:
      - cmd: nextcloud-available_{{ loop.index }}

nextcloud_config_onlyoffice_1_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:install onlyoffice || true'
    - unless: >-
        docker exec --user www-data nextcloud-{{ domain["name"] }}
        php occ --no-warnings app:list --output=json | jq -e '.enabled | has("onlyoffice")'
    - require:
      - cmd: nextcloud-available_{{ loop.index }}

nextcloud_config_onlyoffice_2_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:enable onlyoffice --force || true'
    - unless: >-
        docker exec --user www-data nextcloud-{{ domain["name"] }}
        php occ --no-warnings app:list --output=json | jq -e '.enabled | has("onlyoffice")'
    - require:
      - cmd: nextcloud-available_{{ loop.index }}

nextcloud_config_onlyoffice_3_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:system:set onlyoffice DocumentServerUrl --value={{ domain["onlyoffice"]["DocumentServerUrl"] }}'
    - require:
      - cmd: nextcloud-available_{{ loop.index }}

nextcloud_config_onlyoffice_4_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:system:set onlyoffice DocumentServerInternalUrl --value={{ domain["onlyoffice"]["DocumentServerInternalUrl"] }}'
    - require:
      - cmd: nextcloud-available_{{ loop.index }}

nextcloud_config_onlyoffice_5_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:system:set onlyoffice StorageUrl --value={{ domain["onlyoffice"]["StorageUrl"] }}'
    - require:
      - cmd: nextcloud-available_{{ loop.index }}

    {%- endif %}
    {%- if "collabora" in domain %}
nextcloud_config_collabora_0_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:disable onlyoffice || true'
    - require:
      - cmd: nextcloud-available_{{ loop.index }}

nextcloud_config_collabora_1_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:install richdocuments || true'
    - unless: >-
        docker exec --user www-data nextcloud-{{ domain["name"] }}
        php occ --no-warnings app:list --output=json | jq -e '.enabled | has("richdocuments")'
    - require:
      - cmd: nextcloud-available_{{ loop.index }}

nextcloud_config_collabora_2_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:enable --force richdocuments || true'
    - unless: >-
        docker exec --user www-data nextcloud-{{ domain["name"] }}
        php occ --no-warnings app:list --output=json | jq -e '.enabled | has("richdocuments")'
    - require:
      - cmd: nextcloud-available_{{ loop.index }}

nextcloud_config_collabora_3_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:app:set richdocuments wopi_url --value {{ domain["collabora"]["DocumentServerUrl"] }}'
    - require:
      - cmd: nextcloud-available_{{ loop.index }}

nextcloud_config_collabora_4_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:app:set richdocuments wopi_allowlist --value {{ domain["collabora"]["wopi_allowlist"] }}'
    - require:
      - cmd: nextcloud-available_{{ loop.index }}

      {%- if "doc_format" in domain["collabora"] %}
nextcloud_config_collabora_5_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:app:set richdocuments doc_format --value {{ domain["collabora"]["doc_format"] }}'
    - require:
      - cmd: nextcloud-available_{{ loop.index }}
      {%- endif %}

nextcloud_config_collabora_6_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ richdocuments:activate-config'
    - require:
      - cmd: nextcloud-available_{{ loop.index }}

    {%- endif %}
    {%- if "user_saml" in domain %}

nextcloud_config_user_saml_1_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:install user_saml || true'
    - require:
      - cmd: nextcloud-available_{{ loop.index }}

nextcloud_config_user_saml_2_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings app:enable user_saml'
    - require:
      - cmd: nextcloud-available_{{ loop.index }}

nextcloud_config_user_saml_3_{{ loop.index }}:
  file.serialize:
    - name: /opt/nextcloud/{{ domain["name"] }}/data/.salt_user_saml_config.json
    - user: www-data
    - mode: '0600'
    - show_changes: False
    - dataset:
        apps:
          user_saml: {{ domain["user_saml"] | json }}
    - formatter: json

nextcloud_config_user_saml_4_{{ loop.index }}:
  cmd.run:
    - name: docker exec --user www-data nextcloud-{{ domain["name"] }} bash -c 'php occ --no-warnings config:import < .salt_user_saml_config.json'
    - require:
      - file: nextcloud_config_user_saml_3_{{ loop.index }}
      - cmd: nextcloud-available_{{ loop.index }}

nextcloud_remove_config_user_saml_{{ loop.index }}:
  file.absent:
    - name: /opt/nextcloud/{{ domain["name"] }}/data/.salt_user_saml_config.json
    - require:
      - cmd: nextcloud_config_user_saml_4_{{ loop.index }}

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

