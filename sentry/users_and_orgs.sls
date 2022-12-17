{% if pillar["sentry"] is defined and "users" in pillar["sentry"] %}
  {%- for user in pillar["sentry"]["users"] %}
sentry_user_create_{{ loop.index }}:
  cmd.run:
    - name: docker exec sentry-self-hosted-web-1 sentry createuser --email {{ user["email"] }} {{ "--password " ~ user["password"] if "password" in user else "--no-password" }} {{ "--superuser" if "superuser" in user and user["superuser"] else "--no-superuser" }} {{ "--staff" if "staff" in user and user["staff"] else "--no-staff" }} --force-update --no-input

    {%- if "auth_tokens" in user %}
      {%- set a_loop = loop %}
      {%- for token in user["auth_tokens"] %}
sentry_auth_token_create_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: |
        docker exec sentry-self-hosted-postgres-1 su - postgres -c "psql -c \"
          INSERT INTO sentry_apitoken
            (scopes, scope_list, token, date_added, user_id)
          VALUES
            (
              0,
              '{{ token["scope_list"] }}',
              '{{ token["token"] }}',
              now(),
              (SELECT id FROM auth_user WHERE email = '{{ user["email"] }}')
            )
          ON CONFLICT (token) DO UPDATE SET scope_list = '{{ token["scope_list"] }}'
        \""

      {%- endfor %}
    {%- endif %}
  {%- endfor %}
{%- endif %}

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

    {% if "members" in org %}
      {%- for member in org["members"] %}
sentry_org_member_create_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: |
        docker exec sentry-self-hosted-postgres-1 su - postgres -c "psql -c \"
          INSERT INTO sentry_organizationmember
            (role, flags, date_added, has_global_access, type, organization_id, user_id, invite_status)
          VALUES
            ('{{ member["role"] }}', 0, now(), true, 50, (SELECT id FROM sentry_organization WHERE slug = '{{ org["slug"] }}'), (SELECT id FROM auth_user WHERE email = '{{ member["email"] }}'), 0)
          ON CONFLICT (organization_id, user_id) DO NOTHING;
        \""

      {%- endfor %}
    {%- endif %}

    {% if "teams" in org %}
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
        {%- if "members" in team %}
          {%- for member in team["members"] %}
sentry_org_team_member_create_{{ a_loop.index }}_{{ b_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: |
        docker exec sentry-self-hosted-postgres-1 su - postgres -c "psql -c \"
          INSERT INTO sentry_organizationmember_teams
            (is_active, organizationmember_id, team_id)
          VALUES
            (
              true,
              (
                SELECT id FROM sentry_organizationmember
                WHERE
                  role = (
                    SELECT role FROM sentry_organizationmember
                    WHERE
                      user_id = (SELECT id FROM auth_user WHERE email = '{{ member }}')
                      AND organization_id = (SELECT id FROM sentry_organization WHERE slug = '{{ org["slug"] }}')
                    LIMIT 1
                  )
                  AND organization_id = (SELECT id FROM sentry_organization WHERE slug = '{{ org["slug"] }}')
                  AND user_id = (SELECT id FROM auth_user WHERE email = '{{ member }}')
              ),
              (
                SELECT id FROM sentry_team
                WHERE
                  slug = '{{ team["slug"] }}'
                  AND organization_id = (SELECT id FROM sentry_organization WHERE slug = '{{ org["slug"] }}')
              )
            )
          ON CONFLICT DO NOTHING;
        \""

          {%- endfor %}
        {%- endif %}

      {%- endfor %}
    {%- endif %}

    {%- if "projects" in org %}
      {%- for project in org["projects"] %}
sentry_org_project_create_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: |
        curl -sS {{ pillar["sentry"]["url"] }}/api/0/teams/{{ org["slug"] }}/{{ project["teams"][0] }}/projects/ \
          -H "Authorization: Bearer {{ pillar["sentry"]["auth_token"] }}" \
          -X POST \
          -H "Content-Type: application/json" \
          -d '{"name":"{{ project["name"] }}","slug":"{{ project["slug"] }}"}'

        {%- set b_loop = loop %}
        {%- for team in project["teams"] %}
sentry_org_project_team_create_{{ a_loop.index }}_{{ b_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: |
        docker exec sentry-self-hosted-postgres-1 su - postgres -c "psql -c \"
          INSERT INTO sentry_projectteam
            (project_id, team_id)
          VALUES
            (
              (SELECT id FROM sentry_project WHERE slug = '{{ project["slug"] }}' AND organization_id = (SELECT id FROM sentry_organization WHERE slug = '{{ org["slug"] }}')),
              (SELECT id FROM sentry_team WHERE slug = '{{ team }}' AND organization_id = (SELECT id FROM sentry_organization WHERE slug = '{{ org["slug"] }}'))
            )
          ON CONFLICT DO NOTHING;
        \""

        {%- endfor %}

        {%- if "auto_resolve_issues_30_days" in project and project["auto_resolve_issues_30_days"] %}
sentry_org_project_auto_resolve_issues_30_days_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: |
        docker exec sentry-self-hosted-postgres-1 su - postgres -c "psql -c \"
          INSERT INTO sentry_projectoptions
            (key, value, project_id)
          VALUES
            (
              'sentry:resolve_age',
              'gAJN0AIu',
              (
                SELECT id FROM sentry_project
                WHERE slug = '{{ project["slug"] }}'
                  AND organization_id = (SELECT id FROM sentry_organization WHERE slug = '{{ org["slug"] }}')
              )
            )
          ON CONFLICT (project_id, key) DO UPDATE SET value = 'gAJN0AIu'
            WHERE
              sentry_projectoptions.project_id = 
                (
                  SELECT id FROM sentry_project
                  WHERE slug = '{{ project["slug"] }}'
                    AND organization_id = (SELECT id FROM sentry_organization WHERE slug = '{{ org["slug"] }}')
                )
              AND sentry_projectoptions.key = 'sentry:resolve_age';
        \""

        {%- endif %}

        {%- if "platform" in project %}
sentry_org_project_platform_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: |
        docker exec sentry-self-hosted-postgres-1 su - postgres -c "psql -c \"
          UPDATE sentry_project
          SET platform = '{{ project["platform"] }}'
          WHERE
            slug = '{{ project["slug"] }}'
            AND organization_id = (SELECT id FROM sentry_organization WHERE slug = '{{ org["slug"] }}');
        \""

        {%- endif %}

        {%- if "dsn" in project %}
          {%- for dsn in project["dsn"] %}
sentry_org_project_dsn_create_{{ a_loop.index }}_{{ b_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: |
        docker exec sentry-self-hosted-postgres-1 su - postgres -c "
          if [[ \$(psql --quiet --no-align --tuples-only -c \"
            SELECT COUNT(id) FROM sentry_projectkey
            WHERE
              label = '{{ dsn["label"] }}'
              AND project_id = (
                SELECT id FROM sentry_project
                WHERE slug = '{{ project["slug"] }}'
                  AND organization_id = (SELECT id FROM sentry_organization WHERE slug = '{{ org["slug"] }}')
              )
          \") == 1 ]]; then
            psql -c \"
              UPDATE sentry_projectkey
              SET
                public_key = '{{ dsn["public"] }}',
                secret_key = '{{ dsn["secret"] }}',
                status = 0
              WHERE
                project_id = (
                  SELECT id FROM sentry_project
                  WHERE slug = '{{ project["slug"] }}'
                    AND organization_id = (SELECT id FROM sentry_organization WHERE slug = '{{ org["slug"] }}')
                )
                AND label = '{{ dsn["label"] }}';
            \"
          else
            psql -c \"
              INSERT INTO sentry_projectkey
                (label, public_key, secret_key, roles, status, date_added, data, project_id)
              VALUES
                (
                  '{{ dsn["label"] }}',
                  '{{ dsn["public"] }}',
                  '{{ dsn["secret"] }}',
                  1,
                  0,
                  now(),
                  '{}',
                  (
                    SELECT id FROM sentry_project
                    WHERE slug = '{{ project["slug"] }}'
                      AND organization_id = (SELECT id FROM sentry_organization WHERE slug = '{{ org["slug"] }}')
                  )
                )
            \"
          fi
        "

          {%- endfor %}
        {%- endif %}

      {%- endfor %}
    {%- endif %}
  {%- endfor %}
{%- endif %}
