{% if (pillar['nginx'] is defined) and (pillar['nginx'] is not none) %}
  {%- if (pillar['nginx']['enabled'] is defined) and (pillar['nginx']['enabled'] is not none) and (pillar['nginx']['enabled']) %}
    {%- if (pillar['nginx']['configs'] is defined) and (pillar['nginx']['configs'] is not none) %}
nginx_deps:
  pkg.installed:
    - pkgs:
      - nginx

nginx_files_1:
  file.managed:
    - name: '/etc/nginx/nginx.conf'
    - source: 'salt://{{ pillar['nginx']['configs'] }}/nginx.conf'

nginx_files_2:
  file.absent:
    - name: '/etc/nginx/sites-enabled/default'

nginx_files_4:
  file.managed:
    - name: '/etc/nginx/snippets/ssl-params.conf'
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
        # Disable preloading HSTS for now.  You can use the commented out header line that includes
        # the "preload" directive if you understand the implications.
        #add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload";
        add_header Strict-Transport-Security "max-age=63072000; includeSubdomains";
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        
        ssl_dhparam /etc/ssl/certs/dhparam.pem;

nginx_dhparam:
  cmd.run:
    - name: '[ ! -f /etc/ssl/certs/dhparam.pem ] && openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048 || /bin/true'
    - env:
      - RANDFILE: '/root/.rnd'

    {%- endif %}
  {%- endif %}
{% endif %}

{% if (pillar['nginx'] is defined) and (pillar['nginx'] is not none) %}
  {%- if (pillar['nginx']['forward'] is defined) and (pillar['nginx']['forward'] is not none) %}

    {%- if (pillar['certbot_staging'] is defined) and (pillar['certbot_staging'] is not none) and (pillar['certbot_staging']) %}
      {%- set certbot_staging = "--staging" %}
    {%- else %}
      {%- set certbot_staging = " " %}
    {%- endif %}

    {%- if (pillar['certbot_force_renewal'] is defined) and (pillar['certbot_force_renewal'] is not none) and (pillar['certbot_force_renewal']) %}
      {%- set certbot_force_renewal = "--force-renewal" %}
    {%- else %}
      {%- set certbot_force_renewal = " " %}
    {%- endif %}

    {%- if (pillar['acme_staging'] is defined) and (pillar['acme_staging'] is not none) and (pillar['acme_staging']) %}
      {%- set acme_staging = "--staging" %}
    {%- else %}
      {%- set acme_staging = " " %}
    {%- endif %}

    {%- if (pillar['acme_force_renewal'] is defined) and (pillar['acme_force_renewal'] is not none) and (pillar['acme_force_renewal']) %}
      {%- set acme_force_renewal = "--force" %}
    {%- else %}
      {%- set acme_force_renewal = " " %}
    {%- endif %}

    {%- if (pillar['app_only_one'] is defined) and (pillar['app_only_one'] is not none) %}
      {%- set app_selector = pillar['app_only_one'] %}
    {%- else %}
      {%- set app_selector = 'all' %}
    {%- endif %}
    {%- for forward_app, app_params in pillar['nginx']['forward'].items() -%}
      {%- if
             (app_params['enabled'] is defined) and (app_params['enabled'] is not none) and

             (app_params['nginx'] is defined) and (app_params['nginx'] is not none) and
             (app_params['nginx']['server_name'] is defined) and (app_params['nginx']['server_name'] is not none) and
             (app_params['nginx']['access_log'] is defined) and (app_params['nginx']['access_log'] is not none) and
             (app_params['nginx']['error_log'] is defined) and (app_params['nginx']['error_log'] is not none) and
             (app_params['nginx']['proxy_to'] is defined) and (app_params['nginx']['proxy_to'] is not none) and


             (
               (app_selector == 'all') or
               (app_selector == forward_app)
             )
      %}

      {%- if (app_params['nginx']['ssl'] is defined) and (app_params['nginx']['ssl'] is not none) %}
forward_app_nginx_ssl_dir_{{ loop.index }}:
  file.directory:
    - name: '/etc/nginx/ssl/{{ forward_app }}'
    - user: root
    - group: root
    - makedirs: True
        {%- endif %}

        {%- set server_name_301 = app_params['nginx'].get('server_name_301', forward_app ~ '.example.com') %}
        {%- if
               (app_params['nginx']['ssl'] is defined) and (app_params['nginx']['ssl'] is not none) and
               (app_params['nginx']['ssl']['certs_dir'] is defined) and (app_params['nginx']['ssl']['certs_dir'] is not none) and
               (app_params['nginx']['ssl']['ssl_cert'] is defined) and (app_params['nginx']['ssl']['ssl_cert'] is not none) and
               (app_params['nginx']['ssl']['ssl_key'] is defined) and (app_params['nginx']['ssl']['ssl_key'] is not none) and
               (app_params['nginx']['ssl']['ssl_chain'] is defined) and (app_params['nginx']['ssl']['ssl_chain'] is not none)
        %}
forward_app_nginx_ssl_certs_copy_{{ loop.index }}:
  file.recurse:
    - name: '/etc/nginx/ssl/{{ forward_app }}'
    - source: {{ 'salt://' ~ app_params['nginx']['ssl']['certs_dir'] }}
    - user: root
    - group: root
    - dir_mode: 700
    - file_mode: 600

forward_app_nginx_vhost_config_ssl_custom{{ loop.index }}:
  file.managed:
    - name: '/etc/nginx/sites-available/{{ forward_app }}.conf'
    - user: root
    - group: root
    - source: 'salt://{{ pillar['nginx']['configs'] }}/vhost-http-ssl.conf'
    - template: jinja
    - defaults:
        server_name: {{ app_params['nginx']['server_name'] }}
        server_name_301: '{{ server_name_301 }}'
        proxy_to: {{ app_params['nginx']['proxy_to'] }}
        access_log: {{ app_params['nginx']['access_log'] | default('/var/log/nginx/forward.access.log', true) }}
        error_log: {{ app_params['nginx']['error_log'] | default('/var/log/nginx/forward.error.log', true) }}
        app_root: {{ app_params['app_root'] }}
        ssl_cert: {{ app_params['nginx']['ssl']['ssl_cert'] }}
        ssl_key: {{ app_params['nginx']['ssl']['ssl_key'] }}
        ssl_chain: {{ app_params['nginx']['ssl']['ssl_chain'] }}
        ssl_cert_301: '/etc/nginx/ssl/{{ forward_app }}/301_fullchain.pem'
        ssl_key_301: '/etc/nginx/ssl/{{ forward_app }}/301_privkey.pem'

          {%- if not salt['file.file_exists']('/etc/nginx/ssl/' ~ forward_app ~ '/301_fullchain.pem') %}
forward_app_nginx_ssl_link_1_{{ loop.index }}:
  file.symlink:
    - name: '/etc/nginx/ssl/{{ forward_app }}/301_fullchain.pem'
    - target: '/etc/ssl/certs/ssl-cert-snakeoil.pem'
          {%- endif %}

          {%- if not salt['file.file_exists']('/etc/nginx/ssl/' ~ forward_app ~ '/301_privkey.pem') %}
forward_app_nginx_ssl_link_2_{{ loop.index }}:
  file.symlink:
    - name: '/etc/nginx/ssl/{{ forward_app }}/301_privkey.pem'
    - target: '/etc/ssl/private/ssl-cert-snakeoil.key'
          {%- endif %}

          {%- if
                 (app_params['nginx']['ssl']['certbot_for_301'] is defined) and (app_params['nginx']['ssl']['certbot_for_301'] is not none) and (app_params['nginx']['ssl']['certbot_for_301']) and
                 (app_params['nginx']['ssl']['certbot_email'] is defined) and (app_params['nginx']['ssl']['certbot_email'] is not none) and
                 (pillar['certbot_run_ready'] is defined) and (pillar['certbot_run_ready'] is not none) and (pillar['certbot_run_ready'])
          %}
forward_app_certbot_dir_{{ loop.index }}:
  file.directory:
    - name: '{{ app_params['app_root'] }}/certbot/.well-known'
    - user: {{ app_params['user'] }}
    - group: {{ app_params['group'] }}
    - makedirs: True

forward_app_certbot_run_{{ loop.index }}:
  cmd.run:
    - cwd: /root
    - name: '/opt/certbot/certbot-auto -n certonly --webroot {{ certbot_staging }} {{ certbot_force_renewal }} --reinstall --allow-subset-of-names --agree-tos --cert-name {{ forward_app }} --email {{ app_params['nginx']['ssl']['certbot_email'] }} -w {{ app_params['app_root'] }}/certbot -d "{{ server_name_301|replace(" ", ",") }}"'

forward_app_certbot_replace_symlink_1_{{ loop.index }}:
  cmd.run:
    - cwd: /root
    - name: 'test -f /etc/letsencrypt/live/{{ forward_app }}/fullchain.pem && ln -s -f /etc/letsencrypt/live/{{ forward_app }}/fullchain.pem /etc/nginx/ssl/{{ forward_app }}/301_fullchain.pem || true'

forward_app_certbot_replace_symlink_2_{{ loop.index }}:
  cmd.run:
    - cwd: /root
    - name: 'test -f /etc/letsencrypt/live/{{ forward_app }}/privkey.pem && ln -s -f /etc/letsencrypt/live/{{ forward_app }}/privkey.pem /etc/nginx/ssl/{{ forward_app }}/301_privkey.pem || true'

forward_app_certbot_cron_{{ loop.index }}:
  cron.present:
    - name: '/opt/certbot/certbot-auto renew --renew-hook "service nginx configtest && service nginx restart"'
    - identifier: 'certbot_cron'
    - user: root
    - minute: 10
    - hour: 2
    - dayweek: 1
          {%- endif %}

        {%- elif
               (app_params['nginx']['ssl'] is defined) and (app_params['nginx']['ssl'] is not none) and
               (app_params['nginx']['ssl']['certbot'] is defined) and (app_params['nginx']['ssl']['certbot'] is not none) and (app_params['nginx']['ssl']['certbot']) and
               (app_params['nginx']['ssl']['certbot_email'] is defined) and (app_params['nginx']['ssl']['certbot_email'] is not none)
        %}
forward_app_nginx_vhost_ssl_certbot_config_{{ loop.index }}:
  file.managed:
    - name: '/etc/nginx/sites-available/{{ forward_app }}.conf'
    - user: root
    - group: root
    - source: 'salt://{{ pillar['nginx']['configs'] }}/vhost-http-ssl-acme.conf'
    - template: jinja
    - defaults:
        server_name: {{ app_params['nginx']['server_name'] }}
        server_name_301: '{{ server_name_301 }}'
        proxy_to: {{ app_params['nginx']['proxy_to'] }}
        access_log: {{ app_params['nginx']['access_log'] }}
        error_log: {{ app_params['nginx']['error_log'] }}
        app_root: {{ app_params['app_root'] }}
        ssl_cert: '/etc/nginx/ssl/{{ forward_app }}/fullchain.pem'
        ssl_key: '/etc/nginx/ssl/{{ forward_app }}/privkey.pem'

          {%- if not salt['file.file_exists']('/etc/nginx/ssl/' ~ forward_app ~ '/fullchain.pem') %}
forward_app_nginx_ssl_link_1_{{ loop.index }}:
  file.symlink:
    - name: '/etc/nginx/ssl/{{ forward_app }}/fullchain.pem'
    - target: '/etc/ssl/certs/ssl-cert-snakeoil.pem'
          {%- endif %}

          {%- if not salt['file.file_exists']('/etc/nginx/ssl/' ~ forward_app ~ '/privkey.pem') %}
forward_app_nginx_ssl_link_2_{{ loop.index }}:
  file.symlink:
    - name: '/etc/nginx/ssl/{{ forward_app }}/privkey.pem'
    - target: '/etc/ssl/private/ssl-cert-snakeoil.key'
          {%- endif %}

          {%- if (pillar['certbot_run_ready'] is defined) and (pillar['certbot_run_ready'] is not none) and (pillar['certbot_run_ready']) %}
forward_app_certbot_dir_{{ loop.index }}:
  file.directory:
    - name: '{{ app_params['app_root'] }}/certbot/.well-known'
    - user: {{ app_params['user'] }}
    - group: {{ app_params['group'] }}
    - makedirs: True

forward_app_certbot_run_{{ loop.index }}:
  cmd.run:
    - cwd: /root
    - name: '/opt/certbot/certbot-auto -n certonly --webroot {{ certbot_staging }} {{ certbot_force_renewal }} --reinstall --allow-subset-of-names --agree-tos --cert-name {{ forward_app }} --email {{ app_params['nginx']['ssl']['certbot_email'] }} -w {{ app_params['app_root'] }}/certbot -d "{{ app_params['nginx']['server_name']|replace(" ", ",") }}"'

forward_app_certbot_replace_symlink_1_{{ loop.index }}:
  cmd.run:
    - cwd: /root
    - name: 'test -f /etc/letsencrypt/live/{{ forward_app }}/fullchain.pem && ln -s -f /etc/letsencrypt/live/{{ forward_app }}/fullchain.pem /etc/nginx/ssl/{{ forward_app }}/fullchain.pem || true'

forward_app_certbot_replace_symlink_2_{{ loop.index }}:
  cmd.run:
    - cwd: /root
    - name: 'test -f /etc/letsencrypt/live/{{ forward_app }}/privkey.pem && ln -s -f /etc/letsencrypt/live/{{ forward_app }}/privkey.pem /etc/nginx/ssl/{{ forward_app }}/privkey.pem || true'

forward_app_certbot_cron_{{ loop.index }}:
  cron.present:
    - name: '/opt/certbot/certbot-auto renew --renew-hook "service nginx configtest && service nginx restart"'
    - identifier: 'certbot_cron'
    - user: root
    - minute: 10
    - hour: 2
    - dayweek: 1
          {%- endif %}

        {%- elif
               (app_params['nginx']['ssl'] is defined) and (app_params['nginx']['ssl'] is not none) and
               (app_params['nginx']['ssl']['acme'] is defined) and (app_params['nginx']['ssl']['acme'] is not none) and (app_params['nginx']['ssl']['acme'])
        %}
forward_app_nginx_vhost_ssl_acme_config_{{ loop.index }}:
  file.managed:
    - name: '/etc/nginx/sites-available/{{ forward_app }}.conf'
    - user: root
    - group: root
    - source: 'salt://{{ pillar['nginx']['configs'] }}/vhost-http-ssl-acme.conf'
    - template: jinja
    - defaults:
        server_name: {{ app_params['nginx']['server_name'] }}
          {%- if (app_params['nginx']['server_name_301'] is defined) and (app_params['nginx']['server_name_301'] is not none) %}
        server_name_301: '{{ app_params['nginx']['server_name_301'] }}'
          {%- else %}
        server_name_301: '{{ forward_app }}.example.com'
          {%- endif %}
        proxy_to: {{ app_params['nginx']['proxy_to'] }}
        access_log: {{ app_params['nginx']['access_log'] }}
        error_log: {{ app_params['nginx']['error_log'] }}
        app_root: {{ app_params['nginx']['root'] }}
        ssl_cert: '/etc/nginx/ssl/{{ forward_app }}/fullchain.pem'
        ssl_key: '/etc/nginx/ssl/{{ forward_app }}/privkey.pem'

          {# at least we have snakeoil, if cert req fails #}
          {%- if not salt['file.file_exists']('/etc/nginx/ssl/' ~ forward_app ~ '/fullchain.pem') %}
forward_app_nginx_ssl_link_1_{{ loop.index }}:
  file.symlink:
    - name: '/etc/nginx/ssl/{{ forward_app }}/fullchain.pem'
    - target: '/etc/ssl/certs/ssl-cert-snakeoil.pem'
          {%- endif %}

          {%- if not salt['file.file_exists']('/etc/nginx/ssl/' ~ forward_app ~ '/privkey.pem') %}
forward_app_nginx_ssl_link_2_{{ loop.index }}:
  file.symlink:
    - name: '/etc/nginx/ssl/{{ forward_app }}/privkey.pem'
    - target: '/etc/ssl/private/ssl-cert-snakeoil.key'
          {%- endif %}

          {%- if (pillar['acme_run_ready'] is defined) and (pillar['acme_run_ready'] is not none) and (pillar['acme_run_ready']) %}
forward_app_acme_run_{{ loop.index }}:
  cmd.run:
    - cwd: /opt/acme/home
            {%- if (app_params['nginx']['server_name_301'] is defined) and (app_params['nginx']['server_name_301'] is not none) %}
    - name: '/opt/acme/home/acme_local.sh {{ acme_staging }} {{ acme_force_renewal }} --cert-file /opt/acme/cert/{{ forward_app }}_cert.cer --key-file /opt/acme/cert/{{ forward_app }}_key.key --ca-file /opt/acme/cert/{{ forward_app }}_ca.cer --fullchain-file /opt/acme/cert/{{ forward_app }}_fullchain.cer --issue -d {{ app_params['nginx']['server_name']|replace(" ", " -d ") }} -d {{ app_params['nginx']['server_name_301']|replace(" ", " -d ") }}'
            {%- else %}
    - name: '/opt/acme/home/acme_local.sh {{ acme_staging }} {{ acme_force_renewal }} --cert-file /opt/acme/cert/{{ forward_app }}_cert.cer --key-file /opt/acme/cert/{{ forward_app }}_key.key --ca-file /opt/acme/cert/{{ forward_app }}_ca.cer --fullchain-file /opt/acme/cert/{{ forward_app }}_fullchain.cer --issue -d {{ app_params['nginx']['server_name']|replace(" ", " -d ") }}'
            {%- endif %}

forward_app_acme_replace_symlink_1_{{ loop.index }}:
  cmd.run:
    - cwd: /root
    - name: 'test -f /opt/acme/cert/{{ forward_app }}_fullchain.cer && ln -s -f /opt/acme/cert/{{ forward_app }}_fullchain.cer /etc/nginx/ssl/{{ forward_app }}/fullchain.pem || true'

forward_app_acme_replace_symlink_2_{{ loop.index }}:
  cmd.run:
    - cwd: /root
    - name: 'test -f /opt/acme/cert/{{ forward_app }}_key.key && ln -s -f /opt/acme/cert/{{ forward_app }}_key.key /etc/nginx/ssl/{{ forward_app }}/privkey.pem || true'
          {%- endif %}

        {%- else %}
forward_app_nginx_vhost_config_{{ loop.index }}:
  file.managed:
    - name: '/etc/nginx/sites-available/{{ forward_app }}.conf'
    - user: root
    - group: root
    - source: 'salt://{{ pillar['nginx']['configs'] }}/vhost-http.conf'
    - template: jinja
    - defaults:
        server_name: {{ app_params['nginx']['server_name'] }}
        server_name_301: '{{ server_name_301 }}'
        proxy_to: {{ app_params['nginx']['proxy_to'] }}
        access_log: {{ app_params['nginx']['access_log'] }}
        error_log: {{ app_params['nginx']['error_log'] }}
        app_name: {{ forward_app }}
        {%- endif %}





        {%- if (app_params['enabled']) %}
forward__nginx_enabled_forward__{{ loop.index }}:
  file.symlink:
    - name: '/etc/nginx/sites-enabled/{{ forward_app }}.conf'
    - target: '/etc/nginx/sites-available/{{ forward_app }}.conf'

        {%- endif %}


        {%- if (pillar['nginx']['reload'] is defined) and (pillar['nginx']['reload'] is not none) and (pillar['nginx']['reload']) %}
forward__nginx_reload__{{ loop.index }}:
  cmd.run:
    - runas: 'root'
    - name: 'service nginx configtest && service nginx reload'

        {%- endif %}
      {%- endif %}
    {%- endfor %}

forward_info_warning:
  test.configurable_test_state:
    - name: state_warning
    - changes: False
    - result: True
    - comment: |
        WARNING: State configures nginx virtual hosts, BUT it doesn't reload or restart nginx.
        WARNING: It is done so not to break running production sites on the host.
         NOTICE:
         NOTICE: CERTBOT workflow:
         NOTICE: --------------------------------------------------------------------------------------------------------------
         NOTICE: You should state.apply this state first, then check configs, reload or restart nginx, pfp-fpm manually.
         NOTICE: After that there will be /.well-known/ location ready to serve certbot request.
         NOTICE:
         NOTICE: For the second time you can run:
         NOTICE: state.apply ... pillar='{"certbot_run_ready": True}'
         NOTICE: This will activate certbot execution and active its certs in nginx.
         NOTICE:
         NOTICE: After that you can check and reload again.
         NOTICE:
         NOTICE: Also, not to be temp banned by LE when making test runs, you can run:
         NOTICE: state.apply ... pillar='{"certbot_run_ready": True, "certbot_staging": True}'
         NOTICE: This will add --staging option to certbot. Certificate will be not trusted, but LE will allow much more tests.
         NOTICE:
         NOTICE: After staging experiments you can force renewal with:
         NOTICE: state.apply ... pillar='{"certbot_run_ready": True, "certbot_force_renewal": True}'
         NOTICE: This will add --force-renewal option to certbot.
         NOTICE: --------------------------------------------------------------------------------------------------------------
         NOTICE:
         NOTICE: ACME.SH workflow:
         NOTICE: --------------------------------------------------------------------------------------------------------------
         NOTICE: acme.sh should be configured beforehand. You need to specify pillar acme_run_ready to use it:
         NOTICE: state.apply ... pillar='{"acme_run_ready": True}'
         NOTICE: This will activate acme.sh execution.
         NOTICE:
         NOTICE: Also, not to be temp banned by LE when making test runs, you can run:
         NOTICE: state.apply ... pillar='{"acme_run_ready": True, "acme_staging": True}'
         NOTICE: This will add --staging option to acme.sh. Certificate will be not trusted, but LE will allow much more tests.
         NOTICE:
         NOTICE: After staging experiments you can force renewal with:
         NOTICE: state.apply ... pillar='{"acme_run_ready": True, "acme_force_renewal": True}'
         NOTICE: This will add --force option to acme.sh.
         NOTICE: --------------------------------------------------------------------------------------------------------------
         NOTICE:
         NOTICE: You can run only one app with pillar:
         NOTICE: state.apply ... pillar='{"app_only_one": "<app_name>"}'
         NOTICE:
         NOTICE: You can run 'service nginx configtest && service nginx reload' after each app deploy with pillar:
         NOTICE: state.apply ... pillar='{"nginx_reload": True}'
  {%- endif %}
{%- endif %}

