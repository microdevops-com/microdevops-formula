{%- if pillar["dante"] is defined and pillar["dante"]["server"]["enabled"] %}

  {%- set logdir = pillar["dante"]["server"]["logdir"]|default('/var/log/danted') %}

Dante <> Setup daemon:
  pkg.installed:
    - pkgs:
      - dante-server

Dante <> Fix danted.service:
  file.managed:
    - name: '/etc/systemd/system/danted.service.d/fix_logdir.conf'
    - makedirs: True
    - contents: |
        [Service]

        ReadOnlyDirectories=
        ReadOnlyDirectories=/bin /etc /lib -/lib64 /sbin /usr
  cmd.run:
    - name: '/bin/systemctl --system daemon-reload'
    - onchanges:
      - file: 'Dante <> Fix danted.service'
  service.running:
    - name: 'danted'
    - full_restart: True
    - watch:
      - file: 'Dante <> Fix danted.service'

Dante <> Create log directory:
  file.directory:
    - name: {{ logdir }}
    - user: 'root'
    - group: 'root'
    - mode: '0755'
    - makedirs: True

Dante <> Add logrotate config:
  file.managed:
    - name: '/etc/logrotate.d/danted.conf'
    - user: 'root'
    - group: 'root'
    - mode: '0644'
    - contents: |
        {{ logdir }}/*.log {
          daily
          rotate 31
          missingok
          compress
          copytruncate

{%- endif %}
