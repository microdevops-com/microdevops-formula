{% set ns = namespace() -%}
{% set ns.setupCertbot = False -%}

{% if pillar['app'] is defined -%}
  {% for type in ['php-fpm_apps','static_apps','python_apps'] -%}
    {% if pillar['app'][type] is defined -%}
      {% for appname in pillar['app'][type].keys() -%}
        {% if 'certbot' in pillar['app'][type][appname]['nginx']['ssl'].keys() -%}
          {% if pillar['app'][type][appname]['nginx']['ssl']['certbot'] -%}
            {% set ns.setupCertbot = True -%}
          {% endif -%}
        {% endif -%}
      {% endfor -%}
    {% endif -%}
  {% endfor -%}
{% endif -%}

{% if ns.setupCertbot -%}
install_virtualenv:
  pkg.installed:
    - pkgs:
      - python3-virtualenv

certbot_dir:
  file.directory:
    - name: /opt/certbot
    - user: root
    - group: root
    - dir_mode: 755
    - makedirs: True

certbot_venv:
  virtualenv.managed:
    - name: /opt/certbot/venv
    - pip_upgrade: True
    - cwd: /opt/certbot
    - user: root
    - python: python3

certbot_venv_pip:
  pip.installed:
    - name: certbot
    - user: root
    - bin_env: /opt/certbot/venv/bin/pip3

certbot_binary_symlink_legacy:
  file.symlink:
    - name: /opt/certbot/certbot-auto
    - target: /opt/certbot/venv/bin/certbot
    - force: True
    - user: root
    - group: root
    - makedirs: False

certbot_renew_hook_directory:
  file.directory:
    - name: /etc/letsencrypt/renewal-hooks/post
    - user: root
    - group: root
    - dir_mode: 755
    - makedirs: True

certbot_renew_hook_nginx:
  file.managed:
    - name: /etc/letsencrypt/renewal-hooks/post/nginx-reload.bash
    - user: root
    - group: root
    - mode: 0755
    - contents: |
        #!/usr/bin/env bash
        set -ex
        /usr/bin/env nginx -t && /usr/bin/env nginx -s reload
{% endif -%}
