{%- import_yaml "clickhouse_users/defaults.yaml" as defaults %}
{%- import_yaml "clickhouse_backup/defaults.yaml" as backup_defaults %}
{%- set cfg = pillar.get("clickhouse_users", {}) %}
{%- set regular = cfg.get("users", {}).get("regular", {}) %}
{%- set backup = cfg.get("users", {}).get("backup", {}) %}
{%- set profiles = cfg.get("profiles", {}) %}

{%- if backup | length > 1 %}
  {{ raise("\n>>> CRITICAL: clickhouse_users:users:backup must contain at most one user, got " ~ (backup | length)) }}
{%- endif %}

{#- The backup user (if any) needs a plaintext password - it gets pushed into
    clickhouse_backup's config.yml, which a one-way hash can't reconstruct. #}
{%- set backup_username = none %}
{%- set backup_plaintext = none %}
{%- if backup %}
  {%- set backup_username = backup.keys() | list | first %}
  {%- set backup_user = backup[backup_username] %}
  {%- if not backup_user.get("absent", False) %}
    {%- if not backup_user.get("password") %}
      {{ raise("\n>>> CRITICAL: clickhouse_users:users:backup:" ~ backup_username ~ " must set a plaintext 'password' (not password_hash, not empty) - clickhouse_backup needs it as plaintext") }}
    {%- endif %}
    {%- set backup_plaintext = backup_user["password"] %}
  {%- endif %}
{%- endif %}

{%- set all_users = {} %}
{%- do all_users.update(regular) %}
{%- do all_users.update(backup) %}

{#- Users reference profiles by name (u["profile"]) - catch a deleted/typo'd profile
    here, loudly, rather than let it silently break whichever user references it. #}
{%- for username, u in all_users.items() %}
  {%- set referenced_profile = u.get("profile") %}
  {%- if referenced_profile and referenced_profile not in profiles %}
    {{ raise("\n>>> CRITICAL: clickhouse_users user '" ~ username ~ "' references profile '" ~ referenced_profile ~ "' which is not defined in clickhouse_users:profiles") }}
  {%- endif %}
{%- endfor %}

{%- if profiles %}

clickhouse_users_profiles:
  file.managed:
    - name: {{ defaults["users_d_dir"] }}/{{ defaults["profiles_file"] }}
    - makedirs: True
    - user: root
    - group: clickhouse
    - mode: 640
    - template: jinja
    - source: salt://clickhouse_users/files/profiles.xml.jinja
    - context:
        profiles: {{ profiles | tojson }}
{%- endif %}

{%- for username, u in all_users.items() %}
  {%- set file_path = defaults["users_d_dir"] ~ "/" ~ defaults["file_prefix"] ~ username ~ ".xml" %}

  {%- if u.get("absent", False) %}

clickhouse_users_absent_{{ username }}:
  file.absent:
    - name: {{ file_path }}

  {%- else %}

    {%- if u.get("password_hash") %}
      {%- set password_double_sha1_hex = u["password_hash"] %}
    {%- elif u.get("password") %}
      {%- set password_double_sha1_hex = salt["clickhouse_password.double_sha1_hex"](u["password"]) %}
    {%- else %}
      {{ raise("\n>>> CRITICAL: clickhouse_users user '" ~ username ~ "' needs either 'password' or 'password_hash' set (or 'absent: true')") }}
    {%- endif %}

clickhouse_users_managed_{{ username }}:
  file.managed:
    - name: {{ file_path }}
    - makedirs: True
    - user: root
    - group: clickhouse
    - mode: 640
    - template: jinja
    - source: salt://clickhouse_users/files/user.xml.jinja
    - context:
        username: {{ username }}
        password_double_sha1_hex: {{ password_double_sha1_hex }}
        profile: {{ u.get("profile", none) | tojson }}
        readonly: {{ u.get("readonly", none) | tojson }}
        grants: {{ u.get("grants", []) | tojson }}

  {%- endif %}
{%- endfor %}

{#- Keep clickhouse_backup's config.yml in sync - only when the backup user has a
    plaintext password, and only if that formula was applied on this host already
    (self-healing: if the file doesn't exist yet, this is a no-op and will catch up
    on the next apply once clickhouse_backup has run). #}
{%- if backup_username and backup_plaintext %}

clickhouse_backup_config_username:
  file.replace:
    - name: {{ backup_defaults["config_path"] }}
    - pattern: '^  username: .*$'
    - repl: '  username: "{{ backup_username }}"'
    - onlyif: test -f {{ backup_defaults["config_path"] }}

clickhouse_backup_config_password:
  file.replace:
    - name: {{ backup_defaults["config_path"] }}
    - pattern: '^  password: .*$'
    - repl: '  password: "{{ backup_plaintext }}"'
    - onlyif: test -f {{ backup_defaults["config_path"] }}
{%- endif %}
