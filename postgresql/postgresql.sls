{% if (pillar['postgres'] is defined) and (pillar['postgres'] is not none) %}
include:
  - postgres

  {%- if (pillar['postgres']['local'] is defined) and (pillar['postgres']['local'] is not none) %}
    {%- if (pillar['postgres']['local']['uuid_ossp'] is defined) and (pillar['postgres']['local']['uuid_ossp'] is not none) %}
      {%- if (pillar['postgres']['local']['uuid_ossp']['enabled'] is defined) and (pillar['postgres']['local']['uuid_ossp']['enabled'] is not none) and (pillar['postgres']['local']['uuid_ossp']['enabled']) %}
        {%- if (pillar['postgres']['local']['uuid_ossp']['databases'] is defined) and (pillar['postgres']['local']['uuid_ossp']['databases'] is not none) %}
          {%- for postgres_db_for_ext in pillar['postgres']['local']['uuid_ossp']['databases'] %}
postgres_ext_uuid_ossp_{{ loop.index }}:
  postgres_extension.present:
    - name: uuid-ossp
    - maintenance_db: {{ postgres_db_for_ext }}
          {%- endfor %}
        {%- endif %}
      {%- endif %}
    {%- endif %}
    {%- if (pillar['postgres']['local']['superusers'] is defined) and (pillar['postgres']['local']['superusers'] is not none) %}
      {%- for postgres_su in pillar['postgres']['local']['superusers'] %}
postgres_superusers_{{ loop.index }}:
  postgres_user.present:
    - name: {{ postgres_su }}
    - superuser: True
      {%- endfor %}
    {%- endif %}
  {%- endif %}
{% endif %}
