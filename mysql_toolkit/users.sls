#!jinja|yaml|gpg
{%- for reg_user_string, reg_user_params in pillar["mysql_toolkit"]["users"]["regular"].items() %}

  {%- set reg_user_name, reg_user_host = reg_user_string.split('@') %}
  {%- set
          reg_user_pass_hash,
          reg_user_absent
      =
          reg_user_params["password_hash"],
          reg_user_params["absent"]|default(False)
  %}

  {%- if reg_user_absent %}

MySQL ToolKit <> Users / Regular / Absent > '{{ reg_user_name }}'@'{{ reg_user_host }}':
  mysql_user.absent:
    - name: "{{ reg_user_name }}"
    - host: "{{ reg_user_host }}"
    - init_command: "SET SESSION sql_log_bin=0;"
    - connection_default_file: "/root/.my.cnf"

  {%- else %}

MySQL ToolKit <> Users / Regular / Present > '{{ reg_user_name }}'@'{{ reg_user_host }}':
  mysql_user.present:
    - name: "{{ reg_user_name }}"
    - password_hash: "{{ reg_user_pass_hash }}"
    - host: "{{ reg_user_host }}"
    - connection_default_file: "/root/.my.cnf"

    {%- for reg_user_grant in reg_user_params["grants"] %}
      {%- set
              reg_user_privileges,
              reg_user_on_db,
              reg_user_grant_option
          =
              reg_user_grant["privileges"],
              reg_user_grant["on_db"],
              reg_user_grant["grant_option"]|default(False)
      %}

MySQL ToolKit <> Users / Regular / Grant > '{{ reg_user_privileges }}' on '{{ reg_user_on_db }}' to '{{ reg_user_name }}'@'{{ reg_user_host }}':
  mysql_grants.present:
    - user: "{{ reg_user_name }}"
    - host: "{{ reg_user_host }}"
    - grant: "{{ reg_user_privileges }}"
    - grant_option: "{{ reg_user_grant_option }}"
    - database: "{{ reg_user_on_db }}"
    - connection_default_file: "/root/.my.cnf"
    - require:
        - mysql_user: "{{ reg_user_name }}"

    {%- endfor %}
  {%- endif %}
{%- endfor %}
