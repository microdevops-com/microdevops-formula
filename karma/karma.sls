{% if pillar['karma'] is defined and pillar['karma'] is not none %}

  {% if pillar['acme'] is defined %}

    {% from "acme/macros.jinja" import verify_and_issue %}
    {% set acme = pillar["acme"].keys() | first %}
    {{ verify_and_issue(acme, "karma", pillar["karma"]["domain"]) }}

  {% endif %}

  {% set version = pillar['karma']['version'] %}
  {% set download_url = "https://github.com/prymitive/karma/releases/download/v" + version + "/karma-linux-amd64.tar.gz" %}
  {% set install_dir = "/opt/karma" %}
  {% set extra_args = pillar['karma']['extra_args'] | default("") %}

karma-download:
  file.directory:
    - name: {{ install_dir }}/v{{ version }}
    - mode: '0755'
    - makedirs: True

  archive.extracted:
    - name: {{ install_dir }}/v{{ version }}
    - source: {{ download_url }}
    - user: root
    - group: root
    - skip_verify: True
    - if_missing: {{ install_dir }}/v{{ version }}/karma
    - enforce_toplevel: False

karma-symlink:
  file.symlink:
    - name: {{ install_dir }}/karma
    - target: {{ install_dir }}/v{{ version }}/karma-linux-amd64
    - force: True

karma-config:
  file.managed:
    - name: {{ install_dir }}/karma.yml
    - user: root
    - group: root
    - mode: '0644'
    - contents: |
        {{ pillar['karma']['config'] | indent(8) }}

karma-service:
  file.managed:
    - name: /etc/systemd/system/karma.service
    - user: root
    - group: root
    - mode: '0644'
    - contents: |
        [Unit]
        Description=Alertmanager Service
        After=network.target
        [Service]
        ExecStart={{ install_dir }}/karma --config.file={{ install_dir }}/karma.yml {{ extra_args }}
        Restart=always
        User=root
        WorkingDirectory={{ install_dir }}
        [Install]
        WantedBy=multi-user.target
        
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: /etc/systemd/system/karma.service
      
  service.running:
    - name: karma
    - enable: True
    - require:
      - file: karma-service
      - archive: karma-download
      - file: karma-symlink

karma-restart-if-changes:
  cmd.run:
    - name: systemctl restart karma
    - onchanges:
      - file: /etc/systemd/system/karma.service
      - file: {{ install_dir }}/karma.yml
      - file: {{ install_dir }}/karma
{% endif %}

