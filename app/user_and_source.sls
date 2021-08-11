app_{{ app_type }}_group_{{ loop_index }}:
  group.present:
    - name: {{ app["group"] }}

app_{{ app_type }}_user_homedir_{{ loop_index }}:
  file.directory:
    - name: {{ app["app_root"] }}
    - makedirs: True

app_{{ app_type }}_user_{{ loop_index }}:
  user.present:
    - name: {{ app["user"] }}
    - gid: {{ app["group"] }}
      {%- if "user_home" in app %}
    - home: {{ app["user_home"] }}
      {%- else %}
    - home: {{ app["app_root"] }}
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
    - name: {{ app["app_root"] }}
    - user: {{ app["user"] }}
    - group: {{ app["group"] }}
    - makedirs: True

app_{{ app_type }}_user_ssh_dir_{{ loop_index }}:
  file.directory:
    - name: {{ app["app_root"] ~ "/.ssh" }}
    - user: {{ app["user"] }}
    - group: {{ app["group"] }}
    - mode: 700
    - makedirs: True

      {%- if "app_auth_keys" in app %}
app_{{ app_type }}_user_ssh_auth_keys_{{ loop_index }}:
  file.managed:
    - name: {{ app["app_root"] ~ "/.ssh/authorized_keys" }}
    - user: {{ app["user"] }}
    - group: {{ app["group"] }}
    - mode: 600
    - contents: {{ app["app_auth_keys"] | yaml_encode }}

      {%- endif %}

      {%- if "source" in app %}
        {%- if "repo_key" in app["source"] and "repo_key_pub" in app["source"] %}
app_{{ app_type }}_user_ssh_id_{{ loop_index }}:
  file.managed:
    - name: {{ app["app_root"] ~ "/.ssh/id_repo" }}
    - user: {{ app["user"] }}
    - group: {{ app["group"] }}
    - mode: 0600
    - contents: {{ app["source"]["repo_key"] | yaml_encode }}

app_{{ app_type }}_user_ssh_id_pub_{{ loop_index }}:
  file.managed:
    - name: {{ app["app_root"] ~ "/.ssh/id_repo.pub" }}
    - user: {{ app["user"] }}
    - group: {{ app["group"] }}
    - mode: 0644
    - contents: {{ app["source"]["repo_key_pub"] | yaml_encode }}

        {%- endif %}

        {%- if "ssh_config" in app["source"] %}
app_{{ app_type }}_user_ssh_config_{{ loop_index }}:
  file.managed:
    - name: {{ app["app_root"] ~ "/.ssh/config" }}
    - user: {{ app["user"] }}
    - group: {{ app["group"] }}
    - mode: 0600
    - contents: {{ app["source"]["ssh_config"] | yaml_encode }}

        {%- endif %}

app_{{ app_type }}_app_checkout_{{ loop_index }}:
        {%- if "git" in app["source"] %}
  git.latest:
    - name: {{ app["source"]["git"] }}
    - rev: {{ app["source"]["rev"] }}
    - target: {{ app["source"]["target"] }}
    - branch: {{ app["source"]["branch"] }}
    - force_reset: True
    - force_fetch: True
    - user: {{ app["user"] }}
          {%- if "repo_key" in app["source"] and "repo_key_pub" in app["source"] %}
    - identity: {{ app["app_root"] ~ "/.ssh/id_repo" }}
          {%- endif %}

        {%- endif %}

      {%- endif %}

      {%- if "files" in app %}
app_{{ app_type }}_app_files_{{ loop_index }}:
  file.recurse:
    - name: {{ app["files"]["dst"] }}
    - source: {{ "salt://" ~ app["files"]["src"] }}
    - clean: False
    - user: {{ app["user"] }}
    - group: {{ app["group"] }}
    - dir_mode: 755
    - file_mode: 644

      {%- endif %}
