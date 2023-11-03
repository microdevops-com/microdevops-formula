      {%- if not ("keep_user" in app and app["keep_user"]) %}

app_{{ app_type }}_group_{{ loop_index }}:
  group.present:
    - name: {{ _app_group }}

app_{{ app_type }}_user_{{ loop_index }}:
  user.present:
    - name: {{ _app_user }}
    - gid: {{ _app_group }}
        {%- if "groups" in app %}
    - groups: {{ app["groups"] }}
        {%- endif %}
    - home: {{ consider_user_home }}
    - createhome: False
        {% if app["pass"] == "!" %}
    - password: "{{ app["pass"] }}"
        {% else %}
    - password: "{{ app["pass"] }}"
    - hash_password: True
        {% endif %}
        {%- if "enforce_password" in app and not app["enforce_password"] %}
    - enforce_password: False
        {%- endif %}
    - shell: {{ app["shell"] }}
    - fullname: {{ "application " ~ app_name }}

app_{{ app_type }}_user_homedir_create_{{ loop_index }}:
  file.directory:
    - name: {{ consider_user_home }}
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - makedirs: True

app_{{ app_type }}_user_homedir_userown_{{ loop_index }}:
  file.directory:
    - name: {{ _app_app_root }} # TODO
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - makedirs: True

app_{{ app_type }}_user_ssh_dir_{{ loop_index }}:
  file.directory:
    - name: {{ consider_user_home }}/.ssh
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - mode: 700
    - makedirs: True
      {%- endif %}

      {%- if "app_auth_keys" in app %}
app_{{ app_type }}_user_ssh_auth_keys_{{ loop_index }}:
  ssh_auth.present:
    - user: {{ _app_user }}
    - names: {{ app["app_auth_keys"] }}
      {%- endif %}

      {%- with %}
        {%- set files = app.get("files", {}) %}
        {%- if files is none %}
          {%- set files = {} %}
        {%- endif %}

        # code for legacy "files_source" key and "files_contents" key
        {%- if "files_source" in app or "files_contents" in app %}
          {%- do files.update({"managed": files.get("managed", {})}) %}
          {%- do files["managed"].update({"files_source_contents_legacy": [] }) %}

          {%- set items = [] %}
          {%- do items.extend(app.get("files_contents", [])) %}
          {%- do items.extend(app.get("files_source", [])) %}

          {%- for item in items %}
            {%- do item.update({"name": item.pop("path")})%}
            {%- do files["managed"]["files_source_contents_legacy"].append(item) %}
          {%- endfor %}
        {%- endif %}

        # code for legacy "files" key
        {%- if "src" in files.keys() %}
          {%- do files.update({"recurse": files.get("recurse", {})}) %}
          {%- do files["recurse"].update({"files_legacy": [{"name": app["files"].pop("dst"), "source": app["files"].pop("src")}]}) %}
        {%- endif %}

        # code for legacy "mkdir" key
        {%- if "mkdir" in app %}
          {%- do files.update({"directory": files.get("directory", {})}) %}
          {%- do files["directory"].update({"mkdir_legacy": []}) %}
          {%- for dir in app["mkdir"] %}
             {%- do files["directory"]["mkdir_legacy"].extend([{"name": _app_app_root ~ "/" ~ dir.replace("__APP_NAME__", app_name), "makedirs": True}]) %}
          {%- endfor %}
        {%- endif %}

        {%- set extloop = loop_index %}
        {%- set file_manager_defaults = {"default_user": _app_user, "default_group": _app_group,
                                         "replace_old": "__APP_NAME__", "replace_new": app_name} %}
        {%- include "_include/file_manager/init.sls" with context %}
      {%- endwith %}


      {%- if "source" in app %}
        {%- if "repo_key" in app["source"] and "repo_key_pub" in app["source"] %}
app_{{ app_type }}_user_ssh_id_{{ loop_index }}:
  file.managed:
    - name: {{ consider_user_home }}/.ssh/id_repo
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - mode: 0600
    - contents: {{ app["source"]["repo_key"] | yaml_encode }}

app_{{ app_type }}_user_ssh_id_pub_{{ loop_index }}:
  file.managed:
    - name: {{ consider_user_home }}/.ssh/id_repo.pub
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - mode: 0644
    - contents: {{ app["source"]["repo_key_pub"] | yaml_encode }}

        {%- endif %}

        {%- if "ssh_config" in app["source"] %}
app_{{ app_type }}_user_ssh_config_{{ loop_index }}:
  file.managed:
    - name: {{ consider_user_home }}/.ssh/config
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - mode: 0600
    - contents: {{ app["source"]["ssh_config"] | yaml_encode }}

        {%- endif %}

app_{{ app_type }}_app_checkout_{{ loop_index }}:
        {%- if "git" in app["source"] %}
  git.latest:
    - name: {{ app["source"]["git"] }}
    - target: {{ app["source"]["target"]|replace("__APP_NAME__", app_name) }}
          {%- if "rev" in app["source"] %}
    - rev: {{ app["source"]["rev"] }}
          {%- endif %}
          {%- if "branch" in app["source"] %}
    - branch: {{ app["source"]["branch"] }}
          {%- endif %}
          {%- if pillar["force_reset"] is defined %}
    - force_reset: {{ pillar["force_reset"] }}
          {%- elif app["source"]["force_reset"] is defined %}
    - force_reset: {{ app["source"]["force_reset"] }}
          {%- else %}
    - force_reset: True
          {%- endif %}
    - force_fetch: True
          {%- if (pillar["force_checkout"] is defined and pillar["force_checkout"]) or (app["source"]["force_checkout"] is defined and app["source"]["force_checkout"]) %}
    - force_checkout: True
          {%- endif %}
          {%- if (pillar["force_clone"] is defined and pillar["force_clone"]) or (app["source"]["force_clone"] is defined and app["source"]["force_clone"]) %}
    - force_clone: True
          {%- endif %}
    - user: {{ _app_user }}
          {%- if "repo_key" in app["source"] and "repo_key_pub" in app["source"] %}
    - identity: {{ consider_user_home }}/.ssh/id_repo
          {%- endif %}
          {%- if "extra_opts" in app["source"] %}
            {%- for opt in app["source"]["extra_opts"] %}
    - {{ opt }}
            {%- endfor %}
          {%- endif %}

        {%- endif %}

      {%- endif %}




      {%- if "sudo_rules" in app %}
app_{{ app_type }}_app_sudo_dir_{{ loop_index }}:
  file.directory:
    - name: /etc/sudoers.d
    - user: root
    - group: root
    - mode: 755

        {%- for sudo_user, sudo_rules in app["sudo_rules"].items() %}
          {%- set sudo_user = sudo_user|replace("__APP_NAME__", app_name) %}
app_{{ app_type }}_app_sudo_{{ loop_index }}_{{ loop.index }}:
  file.managed:
    - name: /etc/sudoers.d/{{ sudo_user }}
    - user: root
    - group: root
    - mode: 0440
    - contents: |
          {%- for rule in sudo_rules %}
        {{ sudo_user }} {{ rule }}
          {%- endfor %}

        {%- endfor %}
      {%- endif %}

      {%- if "ssh_keys" in app %}
        {%- for ssh_key in app["ssh_keys"] %}
app_{{ app_type }}_user_app_ssh_id_{{ loop_index }}_{{ loop.index }}:
  file.managed:
    - name: {{ consider_user_home }}/.ssh/{{ ssh_key["file"] }}
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - mode: 0600
    - contents: {{ ssh_key["priv"] | yaml_encode }}

app_{{ app_type }}_user_app_ssh_id_pub_{{ loop_index }}_{{ loop.index }}:
  file.managed:
    - name: {{ consider_user_home }}/.ssh/{{ ssh_key["file"] }}.pub
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - mode: 0644
    - contents: {{ ssh_key["pub"] | yaml_encode }}
        {%- endfor %}
      {%- endif %}

      {%- if "ssh_config" in app %}
app_{{ app_type }}_user_app_ssh_config_{{ loop_index }}:
  file.managed:
    - name: {{ consider_user_home }}/.ssh/config
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - mode: 0600
    - contents: {{ app["ssh_config"] | yaml_encode }}
      {%- endif %}
