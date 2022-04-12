{% if pillar["nginx"] is defined %}
nginx_deps:
  pkg.installed:
    - pkgs:
      - nginx

nginx_files_1:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - source: salt://{{ pillar["nginx"]["configs"] }}/nginx.conf

nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

nginx_files_3:
  file.managed:
    - name: /etc/nginx/snippets/ssl-params.conf
    - contents: |
        # from https://cipherli.st/
        # and https://raymii.org/s/tutorials/Strong_SSL_Security_On_nginx.html
        
        ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
        ssl_prefer_server_ciphers on;
        ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";
        ssl_ecdh_curve secp384r1;
        ssl_session_cache shared:SSL:10m;
        ssl_session_tickets off;
        ssl_stapling on;
        ssl_stapling_verify on;
        resolver 8.8.8.8 1.1.1.1 valid=300s;
        resolver_timeout 5s;
        
        ssl_dhparam /etc/ssl/certs/dhparam.pem;

nginx_dhparam:
  cmd.run:
    - name: '[ ! -f /etc/ssl/certs/dhparam.pem ] && openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048 || /bin/true'
    - env:
      - RANDFILE: /root/.rnd

{% endif %}
