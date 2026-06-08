{%- import_yaml "victorialogs/defaults.yaml" as defaults %}
{%- set cfg = pillar.get("victorialogs", {}) %}

{%- set target = cfg.get("target", defaults["target"]) %}
{%- set data_path = cfg.get("data_path", defaults["data_path"]) %}
{%- set service_args = cfg.get("service_args", defaults["service_args"]) %}
{%- set user = cfg.get("user", defaults["user"]) %}

{%- set version = cfg.get("version", "latest") | string %}
{%- if version == "latest" %}
  {%- set response = salt.http.query(defaults["github"]["tags_url"]) %}
  {%- if not "error" in response and "body" in response %}
    {%- set body = response["body"] | load_json %}
    {%- set version = body["tag_name"] %}
  {%- else %}
    {{ raise("\n>>> CRITICAL: error occured during fetching \"latest\" VictoriaLogs release tag\n>>> remote response: " ~ response ~ "\n>>> remote url: " ~ defaults["github"]["tags_url"]) }}
  {%- endif %}
{%- elif not version.startswith("v") %}
  {%- set version = "v" ~ version %}
{%- endif %}
{%- set arch = grains["osarch"].replace("x86_64", "amd64").replace("aarch64", "arm64") %}
{%- set source = defaults["github"]["source"].format(release=version, arch=arch) %}
{%- set source_hash = defaults["github"]["source_hash"].format(release=version, arch=arch) %}

{%- set archive_name = defaults["salt_cache_dir"] ~ "/" ~ source.split("/")[-1] %}
{%- set target_dir = target.rsplit("/", maxsplit=1)[0] %}

victorialogs_group:
  group.present:
    - name: {{ user }}
    - system: True

victorialogs_user:
  user.present:
    - name: {{ user }}
    - system: True
    - gid: {{ user }}
    - home: {{ data_path }}
    - createhome: False
    - shell: /usr/sbin/nologin
    - require:
      - group: victorialogs_group

victorialogs_archive_download:
  file.managed:
    - name: {{ archive_name }}
    - source: {{ source }}
    - makedirs: True
    - source_hash: {{ source_hash }}

victorialogs_target_dir:
  file.directory:
    - name: {{ target_dir }}
    - makedirs: True
    - user: root
    - group: root

victorialogs_archive_extract:
  cmd.run:
    - name: |
        tar --no-same-owner --directory {{ target_dir }} --extract --file {{ archive_name }} {{ defaults["original_name"] }}
    - user: root
    - group: root
    - shell: /bin/bash
    - require:
      - file: victorialogs_archive_download
      - file: victorialogs_target_dir
    {%- if version != "latest" %}
    - unless:
      - '[[ $({{ target }} -version 2>&1) =~ {{ version }} ]]'
    {%- endif %}

victorialogs_rename:
  file.rename:
    - name: {{ target }}
    - source: {{ target_dir }}/{{ defaults["original_name"] }}
    - force: True
    - onlyif:
      - test -f {{ target_dir }}/{{ defaults["original_name"] }}
    - require:
      - cmd: victorialogs_archive_extract

victorialogs_storage_dir:
  file.directory:
    - name: {{ data_path }}
    - makedirs: True
    - user: {{ user }}
    - group: {{ user }}
    - dir_mode: "0750"
    - recurse:
      - user
      - group
    - require:
      - user: victorialogs_user

victorialogs_systemd_unit:
  file.managed:
    - name: /etc/systemd/system/victorialogs.service
    - require:
      - cmd: victorialogs_archive_extract
      - user: victorialogs_user
      - file: victorialogs_storage_dir
    - contents: |
        [Unit]
        Description=VictoriaLogs
        After=network.target

        [Service]
        Type=simple
        User={{ user }}
        Group={{ user }}
        StartLimitBurst=5
        StartLimitInterval=0
        Restart=on-failure
        RestartSec=1
        ExecStart={{ target }} -storageDataPath={{ data_path }} {{ service_args }}

        [Install]
        WantedBy=multi-user.target

victorialogs_systemd_daemon_reload:
  cmd.run:
    - name: systemctl daemon-reload && systemctl enable victorialogs.service && systemctl restart victorialogs.service
    - onchanges:
      - file: victorialogs_systemd_unit
      - cmd: victorialogs_archive_extract

victorialogs_systemd_running:
  cmd.run:
    - name: systemctl is-active victorialogs.service || systemctl start victorialogs.service
    - require:
      - file: victorialogs_systemd_unit
