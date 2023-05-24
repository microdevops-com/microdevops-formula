{% if pillar["bootstrap"] is defined and "files" in pillar["bootstrap"] %}
{% with %}
  {%- set directory = pillar["bootstrap"]["files"].get("directory", {}) %}
  {%- set dirs = [] %}

  {%- for dir in directory.values() %}
    {%- do dirs.extend(dir) %}
  {%- endfor %}

  {%- for dir in dirs %}
bootstrap_dir_directory_{{ loop.index }}:
  file.directory:
    - name: {{ dir["name"] }}
    # "" - means "None" in term of saltstack documentation, the default
    - user: {{ dir.get("user", "") }}
    - group: {{ dir.get("group", "") }}
    - recurse: {{ dir.get("recurse", "") }}
    - dir_mode: {{ dir.get("dir_mode", "")}}
    - file_mode: {{ dir.get("file_mode", "")}}
    - makedirs: {{ dir.get("makedirs", "false") }}
    - force: {{ dir.get("force","") }}

    {%- set a_loop = loop %}
    {%- for cmd in dir.get("apply", []) %}
bootstrap_file_directory_run_{{ loop.index }}_{{ a_loop.index }}:
  cmd.run:
    - name: {{ cmd }}
    {%- endfor %}
  {%- endfor %}

{% endwith %}

{% with %}
  {%- set managed = pillar["bootstrap"]["files"].get("managed", {}) %}
  {%- set files = [] %}

  # flatten all files from pillar to the list
  {%- if managed is mapping %}
    {%- for file in managed.values() %}
      {%- do files.extend(file) %}
    {%- endfor %}
  {%- elif managed is iterable and managed is not mapping and managed is not string %}
      {%- set files = managed %}
  {%- endif %}

  {%- for file in files %}
    # file can contain or can not contain "values", so we want always add it
    {%- do file.update({"values": file.get("values", {}) }) %}

    # always add "domain" to defaults section of the file.managed
    {%- if "domain" in pillar["bootstrap"] %}
      {%- do file["values"].update({"bootstrap_network_domain": pillar["bootstrap"]["domain"]}) %}
    {%- elif "network" in pillar["bootstrap"] and "domain" in pillar["bootstrap"]["network"] %}
      {%- do file["values"].update({"bootstrap_network_domain": pillar["bootstrap"]["network"]["domain"]}) %}
    {%- else %}
      {%- do file["values"].update({"bootstrap_network_domain": "local"}) %}
    {%- endif %}

bootstrap_file_managed_{{ loop.index }}:
  file.managed:
    - name: {{ file["name"] }}

    # handle both contents and source
    {%- if "source" in file %}
    - source: {{ file["source"] }}
    {% elif "contents" in file %}
    - contents: {{ file["contents"] | yaml_encode }}
    {% endif %}

    # "" - means "None" in term of saltstack documentation, the default
    - user: {{ file.get("user", "") }}
    - group: {{ file.get("group", "") }}
    - mode: {{ file.get("mode", "") }}
    - makedirs: {{ file.get("makedirs", "false") }}
    - dir_mode: {{ file.get("dir_mode", "")}}

    # do not template binary files
    {% if file.get("filetype", "text") == "text" %}
    - template: jinja
    - defaults: {{ file["values"] }}
    {% endif %}

    {%- set a_loop = loop %}
    {%- for cmd in file.get("apply", []) %}
bootstrap_file_managed_run_{{ loop.index }}_{{ a_loop.index }}:
  cmd.run:
    - name: {{ cmd }}
    {%- endfor %}

  {%- endfor %}

  {%- for file in pillar["bootstrap"]["files"].get("absent",[]) %}
bootstrap_file_absent_{{ loop.index }}:
    file.absent:
      - name: {{ file["name"] }}

  {%- endfor %}
{% endwith %}
{% endif %}
