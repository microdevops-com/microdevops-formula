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

    {%- set sections = params.get("ini",{}) %}
    {%- if "tz" in params %}
      {%- do sections.update({"Date":{"date.timezone": params["tz"]} })%}
    {%- endif %}

    {%- if sections %}
      {%- for type in ["cli", "fpm"] %}
php-fpm_timezone_{{ version }}_{{ type }}:
  ini.options_present:
    - name: /etc/php/{{ version }}/{{ type }}/php.ini
    - separator: '='
    - sections: {{ sections }}
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
      {%- if version|float <= 8.1 and "php" ~ version ~ "-ioncube" in params["modules"] %}
      {%- set lib_path = "/usr/lib/php/" ~ version ~ "-ioncube" %}

php-fpm_modules_ioncube_1_{{ loop.index }}:
  file.managed:
    - name: {{ lib_path }}/ioncube_loader_lin_{{ version }}.so
    - makedirs: True
    - user: root
    - group: root
    - source: 'https://microdevopsformula.s3.eu-central-1.amazonaws.com/php-fpm/ioncube/ioncube_loader_lin_{{ version }}.so'
    - skip_verify: True

php-fpm_modules_ioncube_2_{{ loop.index }}:
  file.managed:
    - name: /etc/php/{{ version }}/mods-available/ioncube.ini
    - contents: |
        zend_extension={{ lib_path }}/ioncube_loader_lin_{{ version }}.so

php-fpm_modules_ioncube_3_{{ loop.index }}:
  file.symlink:
    - name: /etc/php/{{ version }}/fpm/conf.d/00-ioncube.ini
    - target: /etc/php/{{ version }}/mods-available/ioncube.ini

      {%- endif %}
    {%- endif %}
  {%- endfor %}
{% endif %}
