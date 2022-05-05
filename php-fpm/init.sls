{% if pillar["php-fpm"] is defined %}
  {%- set php_fpm = pillar["php-fpm"] %}
{% endif %}

{% if php_fpm is defined and "versions" in php_fpm %}
php-fpm_repo_deb:
  pkgrepo.managed:
    - name: deb http://ppa.launchpad.net/ondrej/php/ubuntu {{ grains["oscodename"] }} main
    - dist: {{ grains["oscodename"] }}
    - file: /etc/apt/sources.list.d/ondrej-ubuntu-php-{{ grains["oscodename"] }}.list
    - keyserver: keyserver.ubuntu.com
    - keyid: E5267A6C
    - refresh: True

php-fpm_app_log_dir:
  file.directory:
    - name: /var/log/php
    - makedirs: True
    - user: root
    - group: root
    - mode: 755

  {%- for version, params in php_fpm["versions"].items() %}
php-fpm_installed_{{ loop.index }}:
  pkg.installed:
    - pkgs:
      - php{{ version }}-cli
      - php{{ version }}-fpm

    {%- if "tz" in params %}
      {%- set i_loop = loop %}
      {%- for type in ["cli", "fpm"] %}
php-fpm_timezone_{{ i_loop.index }}_{{ loop.index }}:
  ini.options_present:
    - name: /etc/php/{{ version }}/{{ type }}/php.ini
    - separator: '='
    - sections:
        Date:
          date.timezone: {{ params["tz"] }}
      {%- endfor %}
    {%- endif %}

    {%- if "modules" in params %}
php-fpm_modules_installed_{{ loop.index }}:
  pkg.installed:
    - pkgs:
      {%- for module in params["modules"] %}
        {%- if module != "php" ~ version ~ "-ioncube" %}
      - {{ module }}
        {%- endif %}
      {%- endfor %}

      # ioncube is not supported for 8.0+ php yet
      {%- if version|float < 8.0 and "php" ~ version ~ "-ioncube" in params["modules"] %}
        {%- if version|float == 5.6 %}
          {%- set lib_path = "/usr/lib/php/20131226" %}
        {%- endif %}
        {%- if version|float == 7.0 %}
          {%- set lib_path = "/usr/lib/php/20151012" %}
        {%- endif %}
        {%- if version|float == 7.1 %}
          {%- set lib_path = "/usr/lib/php/20160505" %}
        {%- endif %}
        {%- if version|float == 7.2 %}
          {%- set lib_path = "/usr/lib/php/20170718" %}
        {%- endif %}
        {%- if version|float == 7.3 %}
          {%- set lib_path = "/usr/lib/php/20180731" %}
        {%- endif %}
        {%- if version|float == 7.4 %}
          {%- set lib_path = "/usr/lib/php/20190902" %}
        {%- endif %}
php-fpm_modules_ioncube_1_{{ loop.index }}:
  file.managed:
    - name: {{ lib_path }}/ioncube_loader_lin_{{ version }}.so
    - source: salt://php-fpm/files/ioncube/ioncube_loader_lin_{{ version }}.so

php-fpm_modules_ioncube_2_{{ loop.index }}:
  file.managed:
    - name: /etc/php/{{ version }}/mods-available/ioncube.ini
    - source: salt://php-fpm/files/ioncube/ioncube.ini
    - template: jinja
    - defaults:
        path: {{ lib_path }}/ioncube_loader_lin_{{ version }}.so

php-fpm_modules_ioncube_3_{{ loop.index }}:
  file.symlink:
    - name: /etc/php/{{ version }}/fpm/conf.d/00-ioncube.ini
    - target: /etc/php/{{ version }}/mods-available/ioncube.ini

      {%- endif %}
    {%- endif %}
  {%- endfor %}
{% endif %}
