pyenv:
  enabled: True
  version_3_6_7: True

{% set python_version = '3.6.7' %}

pkg:
  alerta-urlmon:
    when: 'PKG_PKG'
    states:
      - module.run:
          1:
            - name: 'state.sls'
            - mods: 'pyenv.pyenv'
      - group.present:
          1:
            - name: 'alerta-urlmon'
      - file.directory:
          1:
            - name: '/opt/alerta'
            - user: 'root'
            - group: 'root'
            - makedirs: True
      - user.present:
          1:
            - name: 'alerta-urlmon'
            - gid: 'alerta-urlmon'
            - home: '/opt/alerta/urlmon'
            - createhome: True
            - password: '!'
            - shell: '/bin/bash'
            - fullname: 'Alerta URLmon'
      - file.directory:
          1:
            - name: '/opt/alerta/urlmon/src'
            - user: 'alerta-urlmon'
            - group: 'alerta-urlmon'
            - makedirs: True
      - git.latest:
          1:
            - name: 'https://github.com/sysadmws/alerta-urlmon'
            - rev: 'master'
            - target: '/opt/alerta/urlmon/src'
            - branch: 'master'
            - force_reset: True
      - file.directory:
          1:
            - name: '/opt/alerta/urlmon/venv'
            - user: 'alerta-urlmon'
            - group: 'alerta-urlmon'
            - makedirs: True
      - file.managed:
          1:
            - name: '/opt/alerta/urlmon/venv/.python-version'
            - user: 'alerta-urlmon'
            - group: 'alerta-urlmon'
            - mode: '0644'
            - contents: |
                {{ python_version }}
      - pip.installed:
          1:
            - name: pip
            - user: root
            - cwd: /tmp
            - bin_env: /usr/local/pyenv/shims/pip
            - upgrade: True
            - force_reinstall: True
            - reload_modules: True
            - env_vars:
                PYENV_VERSION: '{{ python_version }}'
      - pip.installed:
          1:
            - name: virtualenv
            - user: root
            - cwd: /tmp
            - bin_env: /usr/local/pyenv/shims/pip
            - env_vars:
                PYENV_VERSION: '{{ python_version }}'
      - file.managed:
          1:  
            - name: '/opt/alerta/urlmon/virtualenv-{{ python_version }}'
            - user: 'alerta-urlmon'
            - group: 'alerta-urlmon'
            - mode: '0755'
            - contents: |
                #!/bin/sh
                export PYENV_VERSION='{{ python_version }}'
                /usr/local/pyenv/shims/virtualenv "$@"
      - virtualenv.managed:
          1:
            - name: '/opt/alerta/urlmon/venv'
            - python: /usr/local/pyenv/shims/python
            - user: 'alerta-urlmon'
            - system_site_packages: False
            - venv_bin: '/opt/alerta/urlmon/virtualenv-{{ python_version }}'
            - env_vars:
                PYENV_VERSION: '{{ python_version }}'
      - cmd.run:
          1:
            - cwd: '/opt/alerta/urlmon/src'
            - name: '~/venv/bin/python setup.py install'
            - runas: 'alerta-urlmon'
      - file.managed:
          1:
            - name: '/etc/systemd/system/alerta-urlmon.service'
            - user: 'root'
            - group: 'root'
            - contents: |
                [Unit]
                Description=URL Monitoring for Alerta

                [Service]
                Type=simple
                ExecStart=/opt/alerta/urlmon/venv/bin/alerta-urlmon
                RestartSec=60
                Restart=always
                User=alerta-urlmon
                Group=alerta-urlmon

                [Install]
                WantedBy=default.target
      - module.run:
          1:
            - name: 'state.sls'
            - mods: 'alerta-urlmon.alerta-urlmon'
      - cmd.run:
          1:
            - name: 'systemctl daemon-reload && systemctl restart alerta-urlmon && systemctl enable alerta-urlmon'
