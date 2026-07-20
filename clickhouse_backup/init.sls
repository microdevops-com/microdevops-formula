{%- import_yaml "clickhouse_backup/defaults.yaml" as defaults %}
{%- set cfg = pillar.get("clickhouse_backup", {}) %}

{%- set version = cfg.get("version", defaults["github"]["version"]) | string %}
{%- if not version.startswith("v") %}
  {%- set version = "v" ~ version %}
{%- endif %}
{%- set arch = grains["osarch"].replace("x86_64", "amd64").replace("aarch64", "arm64") %}
{%- set deb_sha256 = cfg.get("deb_sha256", {}).get(arch, defaults["github"]["deb_sha256"].get(arch, "")) %}
{%- if not deb_sha256 %}
  {{ raise("\n>>> CRITICAL: no sha256 known for clickhouse-backup " ~ version ~ " (" ~ arch ~ ")\n>>> set pillar clickhouse_backup:deb_sha256:" ~ arch ~ " when pinning a version without a built-in default") }}
{%- endif %}
{%- set deb_name = "clickhouse-backup_" ~ version[1:] ~ "_" ~ arch ~ ".deb" %}
{%- set deb_url = "https://github.com/" ~ defaults["github"]["repo"] ~ "/releases/download/" ~ version ~ "/" ~ deb_name %}
{%- set deb_local_path = defaults["salt_cache_dir"] ~ "/" ~ deb_name %}

{%- set dump_dir = cfg.get("dump_dir", defaults["dump_dir"]) %}
{%- set local_keep_count = cfg.get("local_keep_count", defaults["local_keep_count"]) %}
{%- set ch = defaults["clickhouse"].copy() %}
{%- do ch.update(cfg.get("clickhouse", {})) %}
{%- if not ch["password"] %}
  {{ raise("\n>>> CRITICAL: clickhouse_backup:clickhouse:password is not set in pillar") }}
{%- endif %}
{%- set patterns = cfg.get("patterns", []) %}
{%- if not patterns %}
  {{ raise("\n>>> CRITICAL: clickhouse_backup:patterns is empty - nothing to back up, set at least one {prefix, tables} entry") }}
{%- endif %}

clickhouse_backup_deb_download:
  file.managed:
    - name: {{ deb_local_path }}
    - source: {{ deb_url }}
    - source_hash: sha256={{ deb_sha256 }}
    - makedirs: True

clickhouse_backup_pkg:
  pkg.installed:
    - sources:
      - clickhouse-backup: {{ deb_local_path }}
    - require:
      - file: clickhouse_backup_deb_download

clickhouse_backup_dump_dir:
  file.directory:
    - name: {{ dump_dir }}
    - makedirs: True
    - user: clickhouse
    - group: clickhouse
    - mode: 750

clickhouse_backup_config:
  file.managed:
    - name: {{ defaults["config_path"] }}
    - makedirs: True
    - user: root
    - group: root
    - mode: 640
    - template: jinja
    - source: salt://clickhouse_backup/files/config.yml.jinja
    - context:
        ch_host: {{ ch["host"] }}
        ch_port: {{ ch["port"] }}
        ch_username: {{ ch["username"] }}
    - require:
      - pkg: clickhouse_backup_pkg

clickhouse_backup_script_dir:
  file.directory:
    - name: {{ defaults["script_dir"] }}
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

clickhouse_backup_run_script:
  file.managed:
    - name: {{ defaults["script_path"] }}
    - user: root
    - group: root
    - mode: 700
    - template: jinja
    - source: salt://clickhouse_backup/files/run.sh.jinja
    - context:
        dump_dir: {{ dump_dir }}
        local_keep_count: {{ local_keep_count }}
        password: {{ ch["password"] }}
        patterns: {{ patterns }}
    - require:
      - pkg: clickhouse_backup_pkg
      - file: clickhouse_backup_dump_dir
