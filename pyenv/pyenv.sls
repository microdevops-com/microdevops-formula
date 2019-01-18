{% set pyenv = pillar.get('pyenv', {}) %}
{% if pyenv.get('enabled', False) %}
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

  {%- if (pillar['pyenv']['version_2_7_13'] is defined) and (pillar['pyenv']['version_2_7_13'] is not none) and (pillar['pyenv']['version_2_7_13']) %}
pyenv_2_7_13_installed:
  pyenv.installed:
    - name: python-2.7.13
  {%- endif %}

  {%- if (pillar['pyenv']['version_2_7_14'] is defined) and (pillar['pyenv']['version_2_7_14'] is not none) and (pillar['pyenv']['version_2_7_14']) %}
pyenv_2_7_14_installed:
  pyenv.installed:
    - name: python-2.7.14
  {%- endif %}

  {%- if (pillar['pyenv']['version_2_7_15'] is defined) and (pillar['pyenv']['version_2_7_15'] is not none) and (pillar['pyenv']['version_2_7_15']) %}
pyenv_2_7_15_installed:
  pyenv.installed:
    - name: python-2.7.15
  {%- endif %}

  {%- if (pillar['pyenv']['version_3_5_2'] is defined) and (pillar['pyenv']['version_3_5_2'] is not none) and (pillar['pyenv']['version_3_5_2']) %}
pyenv_3_5_2_installed:
  pyenv.installed:
    - name: python-3.5.2
  {%- endif %}

  {%- if (pillar['pyenv']['version_3_5_3'] is defined) and (pillar['pyenv']['version_3_5_3'] is not none) and (pillar['pyenv']['version_3_5_3']) %}
pyenv_3_5_3_installed:
  pyenv.installed:
    - name: python-3.5.3
  {%- endif %}

  {%- if (pillar['pyenv']['version_3_5_5'] is defined) and (pillar['pyenv']['version_3_5_5'] is not none) and (pillar['pyenv']['version_3_5_5']) %}
pyenv_3_5_5_installed:
  pyenv.installed:
    - name: python-3.5.5
  {%- endif %}

  {%- if (pillar['pyenv']['version_3_5_6'] is defined) and (pillar['pyenv']['version_3_5_6'] is not none) and (pillar['pyenv']['version_3_5_6']) %}
pyenv_3_5_6_installed:
  pyenv.installed:
    - name: python-3.5.6
  {%- endif %}

  {%- if (pillar['pyenv']['version_3_6_5'] is defined) and (pillar['pyenv']['version_3_6_5'] is not none) and (pillar['pyenv']['version_3_6_5']) %}
pyenv_3_6_5_installed:
  pyenv.installed:
    - name: python-3.6.5
  {%- endif %}

  {%- if (pillar['pyenv']['version_3_6_7'] is defined) and (pillar['pyenv']['version_3_6_7'] is not none) and (pillar['pyenv']['version_3_6_7']) %}
pyenv_3_6_7_installed:
  pyenv.installed:
    - name: python-3.6.7
  {%- endif %}

  {%- if (pillar['pyenv']['version_3_7_1'] is defined) and (pillar['pyenv']['version_3_7_1'] is not none) and (pillar['pyenv']['version_3_7_1']) %}
pyenv_3_7_1_installed:
  pyenv.installed:
    - name: python-3.7.1
  {%- endif %}

pyenv_profile_file:
  file.managed:
    - name: /etc/profile.d/pyenv.sh
    - source: 'salt://pyenv/files/pyenv.sh'
    - mode: 0644

{% endif %}
