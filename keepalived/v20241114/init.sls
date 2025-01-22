{% import_yaml "keepalived/v20241114/build_deps.yaml" as build_deps %}

{% set keepalived_config = "/etc/keepalived/keepalived.conf" %}

{# install from package #}
{% if not keepalived.get("from_source", false) %}

  {% set keepalived_bin = "/usr/sbin/keepalived" %}
keepalived_install_from_package:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - keepalived

{# install from source #}
{% else %}

  {% set reinstall = false %}
  {% set clean = false %}
  {% if pillar.get("keepalived_reinstall", false) %}
    {% set reinstall = true %}
    {% set clean = true %}
  {% elif pillar.get("keepalived_make_clean", false) %}
    {% set clean = true %}
  {% endif %}

  {% set srcar = "/usr/local/src/" ~ keepalived["from_source"].split("/")[-1] %}
  {% set srcdir = "/usr/local/src/keepalived" %}
  {% set prefix = "/usr/local" %}
  {% set keepalived_bin = prefix ~ "/sbin/keepalived" %}


keepalived_install_from_source_prepare_dir:
  file.directory:
    - name: {{ srcdir }}
  {% if reinstall %}
    - clean: True
  {% endif %}

keepalived_install_from_source_prepare:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs: {{ keepalived.get("build_deps", build_deps) }}

  file.managed:
    - name: {{ srcar }}
    - source: {{ keepalived["from_source"] }}
    - skip_verify: True
    - use_etag: True

  cmd.run:
    - name: tar --extract --file {{ srcar }} --strip-components=1 --directory={{ srcdir }}
    - cwd: {{ srcdir }}
    - creates:
       - {{ srcdir }}/autogen.sh

keepalived_install_from_source_autogen:
  cmd.run:
    - name: ./autogen.sh
    - cwd: {{ srcdir }}
    - creates:
       - {{ srcdir }}/configure

keepalived_install_from_source_configure:
  cmd.run:
    - name: ./configure --enable-regex --enable-json --prefix={{ prefix }}
    - cwd: {{ srcdir }}
    - creates:
       - {{ srcdir }}/Makefile

  {% if clean %}
keepalived_install_from_source_make_clean:
  cmd.run:
    - name: make clean
    - cwd: {{ srcdir }}
  file.absent:
    - name: {{ keepalived_bin }}
  {% endif %}

keepalived_install_from_source_make:
  cmd.run:
    - name: make
    - cwd: {{ srcdir }}
    - creates:
       - {{ srcdir }}/bin/keepalived

keepalived_install_from_source_make_install:
  cmd.run:
    - name: make install
    - cwd: {{ srcdir }}
    - creates:
       - {{ keepalived_bin }}
{% endif %}

{%- with %}
  {%- set files = keepalived.get("files", {}) %}
  {% set kcfg = files.get("managed",{}).get("keepalived_config",[]) %}

  {% if kcfg | length == 0 %}
    {{ raise("Error! Keepalived config is arbitrary! Please set the 'keepalived:files:managed:keepalived_config'") }}
  {% elif kcfg | length > 1 %}
    {{ raise("Error! Only one entry is allowed in group 'keepalived:files:managed:keepalived_config', please manage additional files in antother group") }}
  {% endif %}

  {% do kcfg[0].setdefault("name", keepalived_config) %}
  {% do kcfg[0].setdefault("makedirs", "True") %}

  {%- set extloop = 0 %} 
  {%- set file_manager_defaults = {"default_user": "root", "default_group": "root",
                                   "replace_old": "_", "replace_new": "_"} %}
  {%- include "_include/file_manager/init.sls" with context %}
{%- endwith %}


keepalived_systemd_service:
  file.managed:
    - name: /etc/systemd/system/keepalived.service
    - source: salt://keepalived/v20241114/service.tmpl
    - template: jinja
    - context:
       exec: {{ keepalived_bin }}
       config: {{ keepalived_config }}
  service.running:
    - name: keepalived.service
    - enable: True
    - watch:
      - file: keepalived_systemd_service
      - file: /etc/keepalived/keepalived.conf
