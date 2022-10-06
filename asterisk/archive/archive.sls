{% if pillar["asterisk_archive"] is defined and "host" in pillar["asterisk_archive"] %}
{% set user = pillar["asterisk_archive"]["user"] %}
{% set group = pillar["asterisk_archive"]["group"] %}

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

/var/archive/:
  file.directory:
    - user: {{ user }}
    - group: {{ group }}
    - dir_mode: 755

directory_create:
  file.directory:
    - names: {{ pillar["asterisk_archive"]["directory_create"] }}
    - user: {{ user }}
    - group: {{ group }}
    - dir_mode: 755
    - makedirs: True

  ssh_auth.present:
    - user: {{ user }}
    - enc: {{ pillar["asterisk_archive"]["ssh_keys"]["ssh_file"] }} 
    - names: {{ pillar["asterisk_archive"]["ssh_keys"]["pub"] }} 

{%- endif %}



