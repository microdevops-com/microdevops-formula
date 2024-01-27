{#
This state accepts the following data structure:

```yaml
file:
  kind:
    block_name:
      - data1: ...
        data2: ...
```

To override defaults - define the `file_manager_defaults` dict
file_manager_defaults = {"default_user":"", "default_group":"", "replace_old":"empty", "replace_new":"empty"}

# "" - means "None" in term of saltstack documentation, the default
#}

{%- if files is not defined or files is none %}
  {%- set files = {} %}
{%- endif %}

{%- if extloop is not defined %}
  {%- set extloop = 0 %}
{%- endif %}

{%- if file_manager_defaults is not defined %}
  {%- set file_manager_defaults = {} %}
{%- endif %}

{%- set replace = (file_manager_defaults.get("replace_old", "empty"),
                   file_manager_defaults.get("replace_new", "empty")) %}
{%- set user = ("user", file_manager_defaults.get("default_user", "")) %}
{%- set group = ("group", file_manager_defaults.get("default_group", "")) %}


{% with %}
  {%- set kind = "recurse" %}
  {%- for blockname, items in files.get(kind, {}).items() %}
    {%- for item in items %}
file_manager_{{ kind }}_{{ blockname }}_{{ extloop }}_{{ loop.index }}:
  file.{{ kind }}:
    - name: {{ item["name"].replace(*replace) }}
    - source: {{ item["source"].replace(*replace) }}
    - user: {{ item.get(*user) }}
    - group: {{ item.get(*group) }}
    - clean: {{ item.get("clean", False) }}
    - dir_mode: {{ item.get("dir_mode","") }}
    - file_mode: {{ item.get("file_mode","") }}
    {%- endfor %}
  {%- endfor %}
{% endwith %}


{% with %}
  {%- set kind = "directory" %}
  {%- for blockname, items in files.get(kind, {}).items() %}
    {%- for item in items %}
file_manager_{{ kind }}_{{ blockname }}_{{ extloop }}_{{ loop.index }}:
  file.{{ kind }}:
    - name: {{ item["name"].replace(*replace) }}
    - user: {{ item.get(*user) }}
    - group: {{ item.get(*group) }}
    - recurse: {{ item.get("recurse", "") }}
    - dir_mode: {{ item.get("dir_mode", "") }}
    - file_mode: {{ item.get("file_mode", "") }}
    - makedirs: {{ item.get("makedirs", "") }}
    - force: {{ item.get("force","") }}
    - clean: {{ item.get("clean","") }}
      {%- set a_loop = loop %}
      {%- for apply in item.get("apply", []) %}
        {%- if apply is not mapping %}
          {%- set apply = {"cmd": apply} %}
        {%- endif %}
        {%- set cmd = apply["cmd"] %}
        {%- set cwd = apply.get("cwd","") %}
        {%- set runas = apply.get("runas",item.get(*user)) %}
        {%- set only = apply.get("only","always") %}
file_manager_{{ kind }}_apply_{{ blockname }}_{{ extloop }}_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: {{ cmd.replace(*replace) }}
    - runas: {{ runas }}
    - cwd: {{ cwd.replace(*replace) }}
        {%- if only != "always" %}
    - {{ only }}:
      - file: {{ item["name"].replace(*replace) }}
        {%- endif %}
      {%- endfor %}
    {%- endfor %}
  {%- endfor %}
{% endwith %}


{% with %}
  {%- set kind = "symlink" %}
  {%- for blockname, items in files.get(kind, {}).items() %}
    {%- for item in items %}
file_manager_{{ kind }}_{{ blockname }}_{{ extloop }}_{{ loop.index }}:
  file.{{ kind }}:
    - name: {{ item["name"].replace(*replace) }}
    - target: {{ item["target"].replace(*replace) }}
    - user: {{ item.get(*user) }}
    - group: {{ item.get(*group) }}
    - makedirs: {{ item.get("makedirs", "false") }}
    - force: {{ item.get("force","") }}
    {%- endfor %}
  {%- endfor %}
{% endwith %}


{% with %}
  {%- set kind = "managed" %}
  {%- for blockname, items in files.get(kind, {}).items() %}
    {%- for item in items %}
file_manager_{{ kind }}_{{ blockname }}_{{ extloop }}_{{ loop.index }}:
  file.{{ kind }}:
    - name: {{ item["name"].replace(*replace) }}
      {%- if "source" in item %} # handle both contents and source
    - source: {{ item["source"].replace(*replace) }}
      {% elif "contents" in item %}
    - contents: {{ item["contents"].replace(*replace) | yaml_encode }}
      {% endif %}
    - user: {{ item.get(*user) }}
    - group: {{ item.get(*group) }}
    - mode: {{ item.get("mode", "") }}
    - makedirs: {{ item.get("makedirs", "false") }}
    - dir_mode: {{ item.get("dir_mode", "")}}
    - source_hash: {{ item.get("source_hash", "") }}
    - skip_verify: {{ item.get("skip_verify", "") }}
      {% if item.get("filetype", "text") == "text" %} # do not template binary files
    - template: {{ item.get("template", "jinja") }}
    - defaults: {{ item.get("values",{}) }}
      {% endif %}
      {%- set a_loop = loop %}
      {%- for apply in item.get("apply", []) %}
        {%- if apply is not mapping %}
          {%- set apply = {"cmd": apply} %}
        {%- endif %}
        {%- set cmd = apply["cmd"] %}
        {%- set cwd = apply.get("cwd","") %}
        {%- set runas = apply.get("runas",item.get(*user)) %}
        {%- set only = apply.get("only","always") %}
file_manager_{{ kind }}_apply_{{ blockname }}_{{ extloop }}_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: {{ cmd.replace(*replace) }}
    - runas: {{ runas }}
    - cwd: {{ cwd.replace(*replace) }}
        {%- if only != "always" %}
    - {{ only }}:
      - file: {{ item["name"].replace(*replace) }}
        {%- endif %}
      {%- endfor %}
    {%- endfor %}
  {%- endfor %}
{% endwith %}


{# This is the generic structure for the other states from salt.state.file #}
{%- for k in ["recurse", "directory", "symlink", "managed"] %}
  {%- if k in files.keys() %}
    {%- do files.pop(k) %}
  {%- endif %}
{%- endfor%}

{% with %}
  {%- for kind, content in files.items() if kind not in ["absent"] %}
    {%- with %}

    {%- for blockname, items in content.items() %}
      {%- for item in items %}
file_manager_{{ kind }}_{{ blockname }}_{{ extloop }}_{{ loop.index }}:
  file.{{ kind }}:
        {%- if "user" in item.keys() %}
    - user: {{ item["user"].replace(*user) }}
        {%- do item.pop("user")%}
        {%- endif %}
        {%- if "group" in item.keys() %}
    - group: {{ item["group"].replace(*group) }}
        {%- do item.pop("group")%}
        {%- endif %}
        {% for key, value in item.items() %}
          {% set value = value | tojson | replace(*replace) | load_json %}
    - {{ key }}: {{ value | yaml_encode }}
        {%- endfor %}
      {%- endfor %}
    {%- endfor %}

    {%- endwith %}
  {%- endfor %}
{% endwith %}


{% with %}
  {%- set kind = "absent" %}
  {%- for blockname, items in files.get(kind, {}).items() %}
    {%- for item in items %}
file_manager_{{ kind }}_{{ blockname }}_{{ extloop }}_{{ loop.index }}:
  file.{{ kind }}:
    - name: {{ item["name"].replace(*replace) }}
    {%- endfor %}
  {%- endfor %}
{% endwith %}
