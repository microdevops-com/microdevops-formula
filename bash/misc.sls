bash_misc_byobu_bashrc_dir:
  file.directory:
    - name: /usr/share/byobu/profiles
    - makedirs: True

bash_misc_byobu_bashrc:
  file.managed:
    - name: /usr/share/byobu/profiles/bashrc
    - source: salt://bash/files/byobu/bashrc

bash_misc_skel_bashrc:
  file.managed:
    - name: /etc/skel/.bashrc
    - source: salt://bash/files/bashrc/.bashrc

bash_misc_root_bashrc:
  file.managed:
    - name: /root/.bashrc
    - source: salt://bash/files/bashrc/.bashrc
