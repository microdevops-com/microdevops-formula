{% if pillar["asterisk"] is defined and "version" in pillar["asterisk"] %}
{% set version = pillar["asterisk"]["version"] %}
{% set user = pillar["asterisk"]["user"] %}
{% set group = pillar["asterisk"]["group"] %}


asterisk_depencies_installed:
  pkg.installed:
    - pkgs:
      - curl
      - libnewt-dev
      - libssl-dev
      - libncurses5-dev
      - subversion
      - libsqlite3-dev
      - build-essential
      - libjansson-dev
      - libxml2-dev
      - uuid-dev
      - libvpb1
      - sngrep


asterisk_source:
  archive.extracted:
    - name: /usr/src
    - source: http://downloads.asterisk.org/pub/telephony/asterisk/old-releases/asterisk-{{ version }}.tar.gz
    - skip_verify: True
    - keep_source: False


{%- if not salt['file.file_exists']('/usr/src/asterisk-' + version + '/addons/mp3/mpg123.h') %}
install_get_mp3_source:
  cmd.run:
    - name: "./contrib/scripts/get_mp3_source.sh"
    - cwd: /usr/src/asterisk-{{ version }}
    - shell: /bin/bash
{% endif %}


run_configure:
  cmd.run:
    - names: 
      - "./contrib/scripts/install_prereq install"
      - "./configure"
    - cwd: '/usr/src/asterisk-{{ version }}'
    - shell: '/bin/bash'

{% if pillar["asterisk"]["modules"] %}
run_configure_modules:
  cmd.run:
    - names: 
      - "make menuselect.makeopts"
  {% for enableDisable in pillar["asterisk"]["modules"] %}
    {% for modul in pillar["asterisk"]["modules"][enableDisable] %}
      - 'menuselect/menuselect --{{ enableDisable }} {{ modul }} menuselect.makeopts'
    {% endfor %}
  {% endfor %}
    - cwd: '/usr/src/asterisk-{{ version }}'
    - shell: '/bin/bash'
{% endif %} 

run_make_and_install:
  cmd.run:
    - names: 
      - "make"
      - "make install"
{%- if not salt['file.directory_exists']('/etc/asterisk') %}
      - "make samples"
{% endif %}
      - "make config"
      - "ldconfig"      
    - cwd: '/usr/src/asterisk-{{ version }}'
    - shell: '/bin/bash'


add_group_asterisk:
  group.present:
    - system: True
    - name: {{ group }}

add_user_asterisk:
  user.present:
    - name: {{ user }}
    - home: /var/lib/asterisk
    - groups:
      - audio
      - dialout
      - {{ group }}
    {% if salt['group.info']("docker") %}
      - docker
    {% endif %}


asterisk_dir_chmod:
  file.directory:
    - user: {{ user }}
    - group: {{ group }}
    - names:
      - /etc/asterisk
      - /var/lib/asterisk
      - /var/log/asterisk
      - /var/spool/asterisk
    - recurse:
      - user
      - group
      - mode

replace_/etc/default/asterisk:
  file.replace:
    - names: 
      - /etc/default/asterisk:
        - pattern: ^.*AST_USER=.*
        - repl: AST_USER="{{ user }}"
      - /etc/default/asterisk:
        - pattern: ^.*AST_GROUP=.*
        - repl: AST_GROUP="{{ group }}"
      - /etc/asterisk/asterisk.conf:
        - pattern: ^.*runuser =.* 
        - repl: 'runuser = {{ user }}'
      - /etc/asterisk/asterisk.conf:
        - pattern: ^.*rungroup =.* 
        - repl: 'rungroup = {{ group }}'     
    - append_if_not_found: True


{% if pillar["asterisk"]["files"] is defined %}

  {% if pillar["asterisk"]["files"]["/etc/asterisk"] is defined %}
/etc/asterisk/:        
  file.recurse:
    - name: /etc/asterisk/
    - source: {{ pillar["asterisk"]["files"]["/etc/asterisk"] }}
    - include_empty: True
    - clean: False
    - user: {{ user }}
    - group: {{ group }}
    - dir_mode: 755
    - file_mode: 664
  {%- endif %}

{%- endif %}


asterisk_core_reload:
  cmd.run:
    - shell: /bin/bash
    - names: 
      - "asterisk -x 'core reload'"

service_asterisk_enable:
  service.running:
    - name: asterisk
    - enable: True



{%- endif %}
