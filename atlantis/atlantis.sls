{% if pillar['atlantis'] is defined and pillar['atlantis'] is not none %}

  {% from "acme/macros.jinja" import verify_and_issue %}
  {% set acme = pillar["acme"].keys() | first %}
{{ verify_and_issue(acme, "atlantis", pillar["atlantis"]["domain"]) }}

atlantis_data_dirs:
  file.directory:
    - names:
      - /opt/atlantis/bin
      - /opt/atlantis/etc
    - mode: 755
    - user: 0
    - group: 0
    - makedirs: True

atlantis_config:
  file.managed:
    - name: /opt/atlantis/etc/config.yaml
    - mode: 644
    - user: 0
    - group: 0
    - contents: |
        {{ pillar['atlantis']['config'] | indent(8) }}

atlantis_config_repos:
  file.managed:
    - name: /opt/atlantis/etc/repos.yaml
    - mode: 644
    - user: 0
    - group: 0
    - contents: |
        {{ pillar['atlantis']['repos'] | indent(8) }}

atlantis_install_dir:
  file.directory:
    - name: /opt/atlantis/versions/{{ pillar['atlantis']['version'] }}
    - user: 0
    - group: 0
    - mode: '0755'
    - makedirs: True

atlantis_binary:
  archive.extracted:
    - name: /opt/atlantis/versions/{{ pillar['atlantis']['version'] }}
    - source: https://github.com/runatlantis/atlantis/releases/download/v{{ pillar['atlantis']['version'] }}/atlantis_linux_amd64.zip
    - source_hash: https://github.com/runatlantis/atlantis/releases/download/v{{ pillar['atlantis']['version'] }}/checksums.txt
    - user: root
    - group: root
    - enforce_toplevel: False
    - if_missing: /opt/atlantis/versions/{{ pillar['atlantis']['version'] }}/atlantis
    - require:
      - file: atlantis_install_dir

atlantis_symlink:
  file.symlink:
    - name: /opt/atlantis/bin/atlantis
    - target: /opt/atlantis/versions/{{ pillar['atlantis']['version'] }}/atlantis
    - force: True
    - require:
      - archive: atlantis_binary
    - watch_in:
      - service: atlantis

atlantis_systemd_1:
  file.managed:
    - name: /etc/systemd/system/atlantis.service
    - user: 0
    - group: 0
    - mode: 644
    - contents: |
        [Unit]
        Description=Atlantis Service for Terraform PR Automation
        After=network.target
        [Service]
        ExecStart=/opt/atlantis/bin/atlantis server --config /opt/atlantis/etc/config.yaml --repo-config=/opt/atlantis/etc/repos.yaml
        Restart=always
        [Install]
        WantedBy=multi-user.target

systemd-reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: atlantis_systemd_1

atlantis_systemd_2:
  service.running:
    - name: atlantis
    - enable: True

atlantis_systemd_3:
  cmd.run:
    - name: systemctl restart atlantis
    - onchanges:
      - file: atlantis_systemd_1
      - file: atlantis_config
      - file: atlantis_config_repos
      - file: atlantis_symlink
    - require:
      - cmd: systemd-reload
{% endif %}

