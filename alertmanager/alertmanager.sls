{% if pillar['alertmanager'] is defined and pillar['alertmanager'] is not none %}

  {% if pillar['acme'] is defined %}

    {% from "acme/macros.jinja" import verify_and_issue %}
    {% set acme = pillar["acme"].keys() | first %}
    {{ verify_and_issue(acme, "alertmanager", pillar["alertmanager"]["domain"]) }}

  {% endif %}

  {% set version = pillar['alertmanager']['version'] %}
  {% set download_url = "https://github.com/prometheus/alertmanager/releases/download/v" + version + "/alertmanager-" + version + ".linux-amd64.tar.gz" %}
  {% set install_dir = "/opt/alertmanager" %}
  {% set extra_args = pillar['alertmanager']['extra_args'] %}

alertmanager-download:
  file.directory:
    - name: {{ install_dir }}
    - mode: '0755'
    - makedirs: True

  archive.extracted:
    - name: {{ install_dir }}
    - source: {{ download_url }}
    - user: root
    - group: root
    - skip_verify: True
    - if_missing: {{ install_dir }}/alertmanager-{{ version }}.linux-amd64/alertmanager{{ install_dir }}/alertmanager

alertmanager-symlink:
  file.symlink:
    - name: {{ install_dir }}/alertmanager
    - target: {{ install_dir }}/alertmanager-{{ version }}.linux-amd64/alertmanager
    - force: True

alertmanager-config:
  file.managed:
    - name: {{ install_dir }}/alertmanager.yml
    - user: root
    - group: root
    - mode: '0644'
    - contents: |
        {{ pillar['alertmanager']['config'] | indent(8) }}

  {% if "web_config" in pillar["alertmanager"] %}

alertmanager-web.config:
  file.managed:
    - name: {{ install_dir }}/web.config.yml
    - user: root
    - group: root
    - mode: '0644'
    - contents: |
        {{ pillar['alertmanager']['web_config'] | indent(8) }}

  {% endif %}

alertmanager-service:
  file.managed:
    - name: /etc/systemd/system/alertmanager.service
    - user: root
    - group: root
    - mode: '0644'
    - contents: |
        [Unit]
        Description=Alertmanager Service
        After=network.target
        [Service]
        ExecStart={{ install_dir }}/alertmanager --config.file={{ install_dir }}/alertmanager.yml {% if "web_config" in pillar["alertmanager"] -%} --web.config.file={{ install_dir }}/web.config.yml {%- endif %} {{ extra_args }}
        Restart=always
        User=root
        WorkingDirectory={{ install_dir }}
        [Install]
        WantedBy=multi-user.target

  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: /etc/systemd/system/alertmanager.service

  service.running:
    - name: alertmanager
    - enable: True
    - require:
      - file: alertmanager-service
      - archive: alertmanager-download
      - file: alertmanager-symlink

alertmanager-restart-if-changes:
  cmd.run:
    - name: systemctl restart alertmanager
    - onchanges:
      - file: /etc/systemd/system/alertmanager.service
      - file: {{ install_dir }}/alertmanager.yml
      - file: {{ install_dir }}/alertmanager
{% endif %}

