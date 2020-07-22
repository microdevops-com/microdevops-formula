{% if pillar["pyenv"] is defined %}
pyenv_deps_1:
  pkg.installed:
    - pkgs:
      - make
      - build-essential
      - libssl-dev
      - zlib1g-dev
      - libbz2-dev
      - libreadline-dev
      - libsqlite3-dev
      - wget
      - curl
      - llvm
      - python-pip

pyenv_deps_2:
  cmd.run:
    - name: apt-get -y build-dep python3

pyenv_update:
  cmd.run:
    - name: |
        cd /usr/local/pyenv && git pull || true

  {%- for ver, ver_enabled in pillar["pyenv"]["versions"].items() %}
    {%- if ver_enabled %}
pyenv_installed_{{ ver }}:
  pyenv.installed:
    - name: {{ ver }}

    {%- endif %}
  {%- endfor %}

pyenv_profile_file:
  file.managed:
    - name: /etc/profile.d/pyenv.sh
    - source: 'salt://pyenv/files/pyenv.sh'
    - mode: 0644

{% endif %}
