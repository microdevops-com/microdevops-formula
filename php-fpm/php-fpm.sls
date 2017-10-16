{% if (pillar['php-fpm'] is defined) and (pillar['php-fpm'] is not none) %}
  {%- if (pillar['php-fpm']['enabled'] is defined) and (pillar['php-fpm']['enabled'] is not none) and (pillar['php-fpm']['enabled']) %}
php-fpm_repo_deb:
  pkgrepo.managed:
    - name: deb http://ppa.launchpad.net/ondrej/php/ubuntu xenial main
    - dist: xenial
    - file: /etc/apt/sources.list.d/ondrej-ubuntu-php-xenial.list
    - keyserver: keyserver.ubuntu.com
    - keyid: E5267A6C
    - refresh_db: true

    {%- if (pillar['php-fpm']['version_5_6'] is defined) and (pillar['php-fpm']['version_5_6'] is not none) and (pillar['php-fpm']['version_5_6']) %}
php-fpm_5_6_installed:
  pkg.installed:
    - pkgs:
      - php5.6-cli
      - php5.6-fpm

      {%- if (pillar['php-fpm']['modules'] is defined) and (pillar['php-fpm']['modules'] is not none) %}
        {%- if (pillar['php-fpm']['modules']['php5_6'] is defined) and (pillar['php-fpm']['modules']['php5_6'] is not none) %}
php-fpm_5_6_modules_installed:
  pkg.installed:
    - pkgs:
          {%- for pkg_name in pillar['php-fpm']['modules']['php5_6'] %}
            {%- if (pkg_name != 'php5.6-ioncube') %}
      - {{ pkg_name }}
            {%- endif %}
          {%- endfor %}

          {%- for pkg_name in pillar['php-fpm']['modules']['php5_6'] %}
            {%- if (pkg_name == 'php5.6-ioncube') %}
php-fpm_5_6_modules_ioncube_1:
  file.managed:
    - name: '/usr/lib/php/20131226/ioncube_loader_lin_5.6.so'
    - user: root
    - group: root
    - source: 'salt://php-fpm/files/ioncube/ioncube_loader_lin_5.6.so'

php-fpm_5_6_modules_ioncube_2:
  file.managed:
    - name: '/etc/php/5.6/mods-available/ioncube.ini'
    - user: root
    - group: root
    - source: 'salt://php-fpm/files/ioncube/ioncube.ini'
    - template: jinja
    - defaults:
        path: '/usr/lib/php/20131226/ioncube_loader_lin_5.6.so'

php-fpm_5_6_modules_ioncube_3:
  file.symlink:
    - name: '/etc/php/5.6/fpm/conf.d/00-ioncube.ini'
    - target: '/etc/php/5.6/mods-available/ioncube.ini'

            {%- endif %}
          {%- endfor %}

        {%- endif %}
      {%- endif %}
    {%- endif %}
  {%- endif %}
{% endif %}
