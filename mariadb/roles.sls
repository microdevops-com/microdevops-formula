{% if pillar["mariadb"] is defined %}
  {%- if "databases" in pillar["mariadb"] %}
    {%- for db_name, db_params in pillar["mariadb"]["databases"].items() %}
mariadb_database_{{ loop.index }}:
  cmd.run:
    - name: |
        mysql -e 'CREATE DATABASE IF NOT EXISTS `{{ db_name }}` CHARACTER SET {{ db_params["character_set"]|default("utf8mb4") }} COLLATE {{ db_params["collate"]|default("utf8mb4_unicode_ci") }};'

    {%- endfor %}
  {%- endif %}

  {%- if "users" in pillar["mariadb"] %}
    {%- for user_name, user_params in pillar["mariadb"]["users"].items() %}
mariadb_user_user_{{ loop.index }}:
  cmd.run:
    - name: |
        mysql -e 'CREATE USER IF NOT EXISTS `{{ user_name }}`@`{{ user_params["host"] }}`;'

mariadb_user_password_{{ loop.index }}:
  cmd.run:
    - name: |
        mysql -e 'ALTER USER `{{ user_name }}`@`{{ user_params["host"] }}` IDENTIFIED BY "{{ user_params["password"] }}";'

      {%- set i_loop = loop %}
      {%- for on, grants in user_params["grants"].items() %}
        {%- set j_loop = loop %}
        {%- for what in grants %}
mariadb_grant_{{ i_loop.index }}_{{ j_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: |
          {%- if " WITH GRANT OPTION" in what %}
            {%- set what = what|replace(" WITH GRANT OPTION", "") %}
        mysql -e 'GRANT {{ what }} ON {{ on }} TO `{{ user_name }}`@`{{ user_params["host"] }}` WITH GRANT OPTION;'
          {%- else %}
        mysql -e 'GRANT {{ what }} ON {{ on }} TO `{{ user_name }}`@`{{ user_params["host"] }}`;'
          {%- endif %}

        {%- endfor %}
      {%- endfor %}
    {%- endfor %}
  {%- endif %}
{% endif %}
