{% if pillar["sentry"] is defined and "organizations" in pillar["sentry"] and "auth_token" in pillar["sentry"]  %}
  {%- for org in pillar["sentry"]["organizations"] %}
sentry_org_create_{{ loop.index }}:
  cmd.run:
    - name: |
        curl -sS {{ pillar["sentry"]["url"] }}/api/0/organizations/ \
          -H "Authorization: Bearer {{ pillar["sentry"]["auth_token"] }}" \
          -X POST \
          -H "Content-Type: application/json" \
          -d '{"name":"{{ org["name"] }}","slug":"{{ org["slug"] }}"}'

    {%- set a_loop = loop %}
    {%- for team in org["teams"] %}
sentry_org_team_create_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: |
        curl -sS {{ pillar["sentry"]["url"] }}/api/0/organizations/{{ org["slug"] }}/teams/ \
          -H "Authorization: Bearer {{ pillar["sentry"]["auth_token"] }}" \
          -X POST \
          -H "Content-Type: application/json" \
          -d '{"name":"{{ team["name"] }}","slug":"{{ team["slug"] }}"}'

      {%- set b_loop = loop %}
      {%- for project in team["projects"] %}
sentry_org_team_project_create_{{ a_loop.index }}_{{ b_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: |
        curl -sS {{ pillar["sentry"]["url"] }}/api/0/teams/{{ org["slug"] }}/{{ team["slug"] }}/projects/ \
          -H "Authorization: Bearer {{ pillar["sentry"]["auth_token"] }}" \
          -X POST \
          -H "Content-Type: application/json" \
          -d '{"name":"{{ project["name"] }}","slug":"{{ project["slug"] }}"}'

      {%- endfor %}
    {%- endfor %}
  {%- endfor %}
{%- endif %}
