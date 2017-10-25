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

{#
nginx_dir_1:
  file.directory:
    - name: '/etc/nginx/upstream'
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

nginx_dir_2:
  file.directory:
    - name: '/etc/nginx/ssl'
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

nginx_dir_3:
  file.directory:
    - name: '/etc/nginx/sites-enabled'
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

nginx_dir_4:
  file.directory:
    - name: '/etc/nginx/sites-available'
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
#}

    {%- endif %}
  {%- endif %}
{% endif %}
