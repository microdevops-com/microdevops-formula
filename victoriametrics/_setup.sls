{%- import_yaml "victoriametrics/defaults.yaml" as defaults %}
{%- set vm_name = vm_name.replace(".","_") %}
{%- set vm_data = vm_data | tojson | replace("__VM_NAME__", vm_name) | load_json %}

{%- if vm_data["service"].get("platform", none) in defaults["platforms"] %}
  {%- set platform = vm_data["service"]["platform"] %}
  {%- if vm_data["service"].get("version", "latest") == "latest" %}
    {%- import "victoriametrics/_release.sls" as release with context %}
    {%- do vm_data["service"].update({"version": release["latest"]}) %}
  {%- endif %}
  {%- set source = defaults["platforms"][platform]["source"].format(release=vm_data["service"]["version"], name=defaults[kind]["name"], arch=grains["osarch"].replace("x86_64", "amd64")) %}
  {%- set source_hash = defaults["platforms"][platform]["source_hash"].format(release=vm_data["service"]["version"], name=defaults[kind]["name"], arch=grains["osarch"].replace("x86_64", "amd64")) %}
{%- else %}
  {%- set source = vm_data["service"]["source"] %}
  {%- set source_hash = vm_data["service"].get("source_hash", none) %}
{%- endif %}

{%- set archive_name = defaults["salt_cache_dir"] ~ "/" ~ source.split("/")[-1] %}
{%- set service_target = vm_data["service"].get("target", defaults[kind]["target"]) %}

{%- set files = vm_data.get("files", {}) %}
{%- set extloop = vm_name %}
{%- include "_include/file_manager/init.sls" %}

{{ kind }}_{{ vm_name }}_archive_download:
  file.managed:
    - name: {{ archive_name }}
    - source: {{ source }}
    - makedirs: True
    {%- if source_hash %}
    - source_hash: {{ source_hash }}
    {%- else %}
    - skip_verify: True
    {%- endif %}

{{ kind }}_{{ vm_name }}_target_dir:
  file.directory:
    - name: {{ service_target.rsplit("/", maxsplit=1)[0] }}
    - makedirs: True
    - user: root
    - group: root

{{ kind }}_{{ vm_name }}_archive_extract:
  cmd.run:
    - name: |
        tar {{ defaults[kind].get("tar_args","") }} --no-same-owner --directory {{ service_target.rsplit("/", maxsplit=1)[0] }} --extract --file {{ archive_name }} {{ defaults[kind]["original_name"] }}
    - user: root
    - group: root
    - shell: /bin/bash
    - require:
      - file: {{ kind }}_{{ vm_name }}_archive_download
    {%- if vm_data.get("service", {}).get("version", none) %}
    - unless:
      {%- if kind != "vmutils" %}
      - '[[ $({{ service_target }} -version) =~ {{ vm_data["service"]["version"] }} ]]'
      {%- else %}
        {%- for file in defaults[kind]["files"] %}
      - '[[ $({{ service_target }}/{{ file }} -version) =~ {{ vm_data["service"]["version"] }} ]]'
        {%- endfor %}
      {%- endif %}
    {%- endif %}

{%- if kind != "vmutils" %}

  {%- set service_name = kind if vm_name == "main" else kind ~ "-" ~ vm_name %}

  {%- if ( kind in ["vmserver", "vmalert"] ) and vm_data.get("nginx", {}) and vm_data.get("nginx",{}).get("enabled", True) %}
    {%- include "victoriametrics/nginx/init.sls" %}
  {%- endif %}

  {%- do defaults[kind]["args"].update(vm_data.get("args", {})) %}
  {%- do vm_data.setdefault("args", {}).update(defaults[kind]["args"]) %}
  {%- if kind != "vmalert" %}
    {%- set arg_storage = defaults[kind]["arg_storage"] %}
    {%- set data_dir = vm_data.get(arg_storage, defaults[kind]["args"][arg_storage]).format(vm_name=vm_name) %}
    {%- do vm_data["args"].update({arg_storage: data_dir}) %}
  {%- endif %}

  {%- set vmargslist = [] %}
  {%- for k, v in vm_data.get("args", {}).items() %}
    {%- do vmargslist.append("-" ~ k ~ "=" ~ v) %}
  {%- endfor %}

  {%- if kind != "vmalert" %}
{{ kind }}_{{ vm_name }}_storage_dir:
  file.directory:
    - name: {{ vm_data["args"][arg_storage] }}
    - makedirs: True
    - user: root
    - group: root
  {%- endif %}

{{ kind }}_{{ vm_name }}_rename:
  file.rename:
    - name: {{ service_target }}
    - source: {{ service_target.rsplit("/", maxsplit=1)[0] }}/{{ defaults[kind]["original_name"] }}
    - force: True

{{ kind }}_{{ vm_name }}_systemd_unit:
  file.managed:
    - name: /etc/systemd/system/{{ service_name }}.service
    - require:
      - cmd: {{ kind }}_{{ vm_name }}_archive_extract
    - contents: |
        [Unit]
        Description=VictoriaMetrics {{ kind }}
        After=network.target

        [Service]
        Type=simple
        StartLimitBurst=5
        StartLimitInterval=0
        Restart=on-failure
        RestartSec=1
        ExecStart={{ service_target }} {{ " ".join(vmargslist) }}

        [Install]
        WantedBy=multi-user.target

{{ kind }}_{{ vm_name }}_systemd_daemon-reload:
  service.running:
    - name: {{ service_name }}.service
    - enable: True
    - require:
      - cmd: {{ kind }}_{{ vm_name }}_archive_extract
    - watch:
      - file: {{ kind }}_{{ vm_name }}_systemd_unit
      - cmd: {{ kind }}_{{ vm_name }}_archive_extract
{%- endif %}
