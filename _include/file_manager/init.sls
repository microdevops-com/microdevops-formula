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

{%- if extloop is not defined or extloop is none %}
  {%- set extloop = 0 %}
{%- endif %}

{%- if file_manager_defaults is not defined or file_manager_defaults is none %}
  {%- set file_manager_defaults = {} %}
{%- endif %}

{%- set replace = (file_manager_defaults.get("replace_old", "empty"),
                   file_manager_defaults.get("replace_new", "empty")) %}
{%- set user = ("user", file_manager_defaults.get("default_user", "")) %}
{%- set group = ("group", file_manager_defaults.get("default_group", "")) %}
{%- set files = files | tojson | replace(*replace) | load_json %}

{%- if hook is not defined %}
  {%- set hook = none %}
{% endif %}

{# namespace files from outer scope #}
{%- set ns = namespace(files={}) %}

{%- for kind in files.keys() %}
  {%- for blockname, items in files[kind].items() %}
    {%- set requisite_packed = items | selectattr("requisite", "defined") | list %}

    {%- if requisite_packed %}
      {%- set requisite = requisite_packed[0]["requisite"] %}
      {%- for req in requisite_packed %}
        {%- do items.remove(req) %}
      {%- endfor %}
    {%- else %}
      {%- set requisite = false %}
    {%- endif %}

    {# no requisites and no hooks, render it right now #}
    {%- if not requisite and hook is none %}
      {%- do ns.files.setdefault(kind,{}).setdefault(blockname,[]).extend(items) %}

    {# only salt's requisites defined, update items and render right now #}
    {%- elif requisite and "hook" not in requisite.keys() and hook is none %}
      {%- for item in items %}
        {%- do item.update({"requisite": requisite}) %}
        {%- do ns.files.setdefault(kind,{}).setdefault(blockname,[]).append(item) %}
      {%- endfor %}

    {# hook (and optional salt's requisites) is defined, and render only if we are in the right place #}
    {%- elif requisite and "hook" in requisite.keys() %}
      {%- if hook == requisite["hook"] %}
        {%- do requisite.pop("hook") %}
        {%- for item in items if requisite %}
          {%- do item.update({"requisite": requisite}) %}
        {%- endfor %}
        {%- do ns.files.setdefault(kind,{}).setdefault(blockname,[]).extend(items) %}
      {%- endif %}
    {%- endif %}

  {%- endfor %}
{%- endfor %}


{%- with %}
  {%- set kind = "recurse" %}
  {%- for blockname, items in ns.files.get(kind, {}).items() %}
    {%- for item in items %}
file_manager_{{ kind }}_{{ blockname }}_{{ extloop }}_{{ loop.index }}:
  file.{{ kind }}:
    - name: {{ item["name"] }}
    - source: {{ item["source"] }}
    - user: {{ item.get(*user) }}
    - group: {{ item.get(*group) }}
    - clean: {{ item.get("clean", False) }}
    - dir_mode: {{ item.get("dir_mode","") }}
    - file_mode: {{ item.get("file_mode","") }}
      {%- if "requisite" in item %}
    - {{ item["requisite"] }}
      {%- endif %}
    {%- endfor %}
  {%- endfor %}
{%- endwith %}


{%- with %}
  {%- set kind = "directory" %}
  {%- for blockname, items in ns.files.get(kind, {}).items() %}
    {%- for item in items %}
file_manager_{{ kind }}_{{ blockname }}_{{ extloop }}_{{ loop.index }}:
  file.{{ kind }}:
    - name: {{ item["name"] }}
    - user: {{ item.get(*user) }}
    - group: {{ item.get(*group) }}
    - recurse: {{ item.get("recurse", "") }}
    - dir_mode: {{ item.get("dir_mode", "") }}
    - file_mode: {{ item.get("file_mode", "") }}
    - makedirs: {{ item.get("makedirs", "") }}
    - force: {{ item.get("force","") }}
    - clean: {{ item.get("clean","") }}
      {%- if "requisite" in item %}
    - {{ item["requisite"] }}
      {%- endif %}
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
    - name: {{ cmd }}
    - runas: {{ runas }}
    - cwd: {{ cwd }}
        {%- if only != "always" %}
    - {{ only }}:
      - file: {{ item["name"] }}
        {%- endif %}
      {%- endfor %}
    {%- endfor %}
  {%- endfor %}
{%- endwith %}


{%- with %}
  {%- set kind = "symlink" %}
  {%- for blockname, items in ns.files.get(kind, {}).items() %}
    {%- for item in items %}
file_manager_{{ kind }}_{{ blockname }}_{{ extloop }}_{{ loop.index }}:
  file.{{ kind }}:
    - name: {{ item["name"] }}
    - target: {{ item["target"] }}
    - user: {{ item.get(*user) }}
    - group: {{ item.get(*group) }}
    - makedirs: {{ item.get("makedirs", "false") }}
    - force: {{ item.get("force","") }}
      {%- if "requisite" in item %}
    - {{ item["requisite"] }}
      {%- endif %}
    {%- endfor %}
  {%- endfor %}
{%- endwith %}


{%- with %}
  {%- set kind = "managed" %}
  {%- for blockname, items in ns.files.get(kind, {}).items() %}
    {%- for item in items %}
file_manager_{{ kind }}_{{ blockname }}_{{ extloop }}_{{ loop.index }}:
  file.{{ kind }}:
    - name: {{ item["name"] }}
      {%- if "source" in item %} {# handle both contents and source #}
    - source: {{ item["source"] }}
      {%- elif "contents" in item %}
    - contents: {{ item["contents"] | yaml_encode }}
      {%- endif %}
    - user: {{ item.get(*user) }}
    - group: {{ item.get(*group) }}
    - mode: {{ item.get("mode", "") }}
    - makedirs: {{ item.get("makedirs", "false") }}
    - dir_mode: {{ item.get("dir_mode", "")}}
    - source_hash: {{ item.get("source_hash", "") }}
    - skip_verify: {{ item.get("skip_verify", "") }}
      {%- if item.get("filetype", "text") == "text" %} {# do not template binary files #}
    - template: {{ item.get("template", "jinja") }}
    - defaults: {{ item.get("values",{}) }}
      {%- endif %}
      {%- if "requisite" in item %}
    - {{ item["requisite"] }}
      {%- endif %}
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
    - name: {{ cmd }}
    - runas: {{ runas }}
    - cwd: {{ cwd }}
        {%- if only != "always" %}
    - {{ only }}:
      - file: {{ item["name"] }}
        {%- endif %}
      {%- endfor %}
    {%- endfor %}
  {%- endfor %}
{%- endwith %}


{# This is the generic structure for the other states from salt.state.file #}
{%- with %}
  {%- for kind, content in ns.files.items() if kind not in ["recurse", "directory", "symlink", "managed", "absent"] %}
    {%- with %}

    {%- for blockname, items in content.items() %}
      {%- for item in items %}
file_manager_{{ kind }}_{{ blockname }}_{{ extloop }}_{{ loop.index }}:
  file.{{ kind }}:
        {%- if "user" in item.keys() %}
    - user: {{ item.get(*user) }}
        {%- do item.pop("user")%}
        {%- endif %}
        {%- if "group" in item.keys() %}
    - group: {{ item.get(*group) }}
        {%- do item.pop("group")%}
        {%- endif %}
        {%- for key, value in item.items() %}
          {%- if key == "requisite" %}
    - {{ item["requisite"] }}
          {%- elif value is string %}
    - {{ key }}: {{ value | yaml_encode }}
          {%- else %}
    - {{ key }}: {{ value }}
          {%- endif %}
        {%- endfor %}
      {%- endfor %}
    {%- endfor %}

    {%- endwith %}
  {%- endfor %}
{%- endwith %}


{%- with %}
  {%- set kind = "absent" %}
  {%- for blockname, items in ns.files.get(kind, {}).items() %}
    {%- for item in items %}
file_manager_{{ kind }}_{{ blockname }}_{{ extloop }}_{{ loop.index }}:
  file.{{ kind }}:
    - name: {{ item["name"] }}
      {%- if "requisite" in item %}
    - {{ item["requisite"] }}
      {%- endif %}
    {%- endfor %}
  {%- endfor %}
{%- endwith %}
