      {%- if not ("keep_user" in app and app["keep_user"]) %}
app_{{ app_type }}_group_{{ loop_index }}:
  group.present:
    - name: {{ _app_group }}

app_{{ app_type }}_user_homedir_{{ loop_index }}:
  file.directory:
    - name: {{ _app_app_root }}
    - makedirs: True

app_{{ app_type }}_user_{{ loop_index }}:
  user.present:
    - name: {{ _app_user }}
    - gid: {{ _app_group }}
        {%- if "user_home" in app %}
    - home: {{ app["user_home"] }}
        {%- else %}
    - home: {{ _app_app_root }}
        {%- endif %}
    - createhome: True
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

app_{{ app_type }}_user_homedir_userown_{{ loop_index }}:
  file.directory:
    - name: {{ _app_app_root }}
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - makedirs: True

        {%- if "mkdir" in app %}
          {%- for dir in app["mkdir"] %}
app_{{ app_type }}_mkdir_{{ loop_index }}_{{ loop.index }}:
  file.directory:
    - name: {{ _app_app_root }}/{{ dir|replace("__APP_NAME__", app_name) }}
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - makedirs: True

          {%- endfor %}
        {%- endif %}

app_{{ app_type }}_user_ssh_dir_{{ loop_index }}:
  file.directory:
    - name: {{ _app_app_root }}/.ssh
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

      {%- if "source" in app %}
        {%- if "repo_key" in app["source"] and "repo_key_pub" in app["source"] %}
app_{{ app_type }}_user_ssh_id_{{ loop_index }}:
  file.managed:
    - name: {{ _app_app_root }}/.ssh/id_repo
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - mode: 0600
    - contents: {{ app["source"]["repo_key"] | yaml_encode }}

app_{{ app_type }}_user_ssh_id_pub_{{ loop_index }}:
  file.managed:
    - name: {{ _app_app_root }}/.ssh/id_repo.pub
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - mode: 0644
    - contents: {{ app["source"]["repo_key_pub"] | yaml_encode }}

        {%- endif %}

        {%- if "ssh_config" in app["source"] %}
app_{{ app_type }}_user_ssh_config_{{ loop_index }}:
  file.managed:
    - name: {{ _app_app_root }}/.ssh/config
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - mode: 0600
    - contents: {{ app["source"]["ssh_config"] | yaml_encode }}

        {%- endif %}

app_{{ app_type }}_app_checkout_{{ loop_index }}:
        {%- if "git" in app["source"] %}
  git.latest:
    - name: {{ app["source"]["git"] }}
    - rev: {{ app["source"]["rev"] }}
    - target: {{ app["source"]["target"]|replace("__APP_NAME__", app_name) }}
    - branch: {{ app["source"]["branch"] }}
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
    - identity: {{ _app_app_root }}/.ssh/id_repo
          {%- endif %}

        {%- endif %}

      {%- endif %}

      {%- if "files" in app %}
app_{{ app_type }}_app_files_{{ loop_index }}:
  file.recurse:
    - name: {{ app["files"]["dst"]|replace("__APP_NAME__", app_name) }}
    - source: {{ app["files"]["src"]|replace("__APP_NAME__", app_name) }}
    - clean: False
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - dir_mode: 755
    - file_mode: 644

      {%- endif %}
