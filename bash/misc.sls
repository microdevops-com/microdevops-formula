bash_misc_byobu_bashrc_dir:
  file.directory:
    - name: /usr/share/byobu/profiles
    - makedirs: True

bash_misc_byobu_bashrc:
  file.managed:
    - name: /usr/share/byobu/profiles/bashrc
    - source: salt://bash/files/byobu/bashrc
    - show_changes: False

{% if grains["oscodename"] in ["xenial", "bionic", "focal", "jammy"] %}
bash_misc_skel_bashrc:
  file.managed:
    - name: /etc/skel/.bashrc
    - source: salt://bash/files/bashrc/.bashrc
    - show_changes: False

bash_misc_root_bashrc:
  file.managed:
    - name: /root/.bashrc
    - source: salt://bash/files/bashrc/.bashrc
    - show_changes: False

  {%- if pillar["users"] is defined %}
    {%- for name, user in pillar["users"].items() %}
      {%- if "home" in user and not ("skip_bashrc" in user and user["skip_bashrc"]) %}
bash_misc_{{ name }}_bashrc:
  file.managed:
    - name: {{ user["home"] }}/.bashrc
    - source: salt://bash/files/bashrc/.bashrc
    - show_changes: False
    - user: {{ name }}
        {%- if "prime_group" in user and "name" in user["prime_group"] %}
    - group: {{ user["prime_group"]["name"] }}
        {%- else %}
    - group: {{ name }}
        {%- endif %}
      {%- endif %}
    {%- endfor %}
  {%- endif %}
{% endif %}
