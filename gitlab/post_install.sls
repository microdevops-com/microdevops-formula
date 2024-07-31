{% if pillar['gitlab']['post_install'] is defined %}

create_post_install_script:
  file.managed:
    - name: /opt/gitlab/post_install.sh
    - contents_pillar: gitlab:post_install
    - mode: 755

run_post_install_script:
  cmd.run:
    - name: /opt/gitlab/post_install.sh
    - runas: root
    - shell: /bin/bash
    - require:
      - file: /opt/gitlab/post_install.sh

{% endif %}
