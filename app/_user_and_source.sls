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
        {%- if "groups" in app %}
    - groups: {{ app["groups"] }}
        {%- endif %}
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
    - identity: {{ _app_app_root }}/.ssh/id_repo
          {%- endif %}
          {%- if "extra_opts" in app["source"] %}
            {%- for opt in app["source"]["extra_opts"] %}
    - {{ opt }}
            {%- endfor %}
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

      {%- if "files_source" in app %}
        {%- for f_s in app["files_source"] %}
app_{{ app_type }}_app_files_source_{{ loop_index }}_{{ loop.index }}:
  file.managed:
    - name: {{ f_s["path"]|replace("__APP_NAME__", app_name) }}
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - mode: {{ f_s["mode"] }}
    - source: {{ f_s["source"] | replace("__APP_NAME__", app_name) }}

        {%- endfor %}
      {%- endif %}

      {%- if "files_contents" in app %}
        {%- for f_c in app["files_contents"] %}
app_{{ app_type }}_app_files_contents_{{ loop_index }}_{{ loop.index }}:
  file.managed:
    - name: {{ f_c["path"]|replace("__APP_NAME__", app_name) }}
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - mode: {{ f_c["mode"] }}
    - contents: {{ f_c["contents"] | replace("__APP_NAME__", app_name) | yaml_encode }}

        {%- endfor %}
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
    - name: {{ _app_app_root }}/.ssh/{{ ssh_key["file"] }}
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - mode: 0600
    - contents: {{ ssh_key["priv"] | yaml_encode }}

app_{{ app_type }}_user_app_ssh_id_pub_{{ loop_index }}_{{ loop.index }}:
  file.managed:
    - name: {{ _app_app_root }}/.ssh/{{ ssh_key["file"] }}.pub
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - mode: 0644
    - contents: {{ ssh_key["pub"] | yaml_encode }}

        {%- endfor %}
      {%- endif %}

      {%- if "ssh_config" in app %}
app_{{ app_type }}_user_app_ssh_config_{{ loop_index }}:
  file.managed:
    - name: {{ _app_app_root }}/.ssh/config
    - user: {{ _app_user }}
    - group: {{ _app_group }}
    - mode: 0600
    - contents: {{ app["ssh_config"] | yaml_encode }}

      {%- endif %}
