{% if pillar["rancher"] is defined %}
  {%- if grains["fqdn"] in pillar["rancher"]["command_hosts"] %}

    {%- if "users" in pillar["rancher"] %}
      {%- for user in pillar["rancher"]["users"] %}
rancher_user_{{ loop.index }}:
  cmd.run:
    - name: |
        # Get users with name and get id of first
        USER_ID=$(curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" \
          --get --data-urlencode "username={{ user["username"] }}" \
          "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/users" | jq .data | jq -r .[].id | head -n 1)
        if [[ -n ${USER_ID} ]]; then
          # Update user
          curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" -X PUT -H 'Accept: application/json' -H 'Content-Type: application/json' -d '{
            "username": "{{ user["username"] }}",
            "description": "{{ user["description"] }}",
            "me": false,
            "mustChangePassword": {{ 'true' if user["must_change_password"] else 'false' }},
            "name": "{{ user["name"] }}",
            "password": "{{ user["password"] }}",
            "principalIds": ["local://'${USER_ID}'"]
          }' "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/users/${USER_ID}"
        else
          # Create user
          curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" -X POST -H 'Accept: application/json' -H 'Content-Type: application/json' -d '{
            "username": "{{ user["username"] }}",
            "description": "{{ user["description"] }}",
            "me": false,
            "mustChangePassword": {{ 'true' if user["must_change_password"] else 'false' }},
            "name": "{{ user["name"] }}",
            "password": "{{ user["password"] }}",
            "principalIds": []
          }' "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/users"
        fi
        # Get user to check role bindings
        USER_ID=$(curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" \
          --get --data-urlencode "username={{ user["username"] }}" \
          "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/users" | jq .data | jq -r .[].id | head -n 1)
        if [[ -z ${USER_ID} ]]; then
          echo username not found
          exit 1
        fi
        # Get all bindings by user to remove - we do not update - remove all and then add needed
        BINDINGS=$(curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" \
          --get --data-urlencode "userId=${USER_ID}" \
          "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/globalrolebindings" | jq .data | jq -r .[].id)
        for BINDING in ${BINDINGS}; do
          curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" -X DELETE -H 'Accept: application/json' "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/globalrolebindings/${BINDING}"
        done
        # Create membership
        curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" -X POST -H 'Accept: application/json' -H 'Content-Type: application/json' -d '{
          "globalRoleId": "{{ user["global_permissions"] }}",
          "userId": "'${USER_ID}'"
        }' "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/globalrolebindings"

        {%- if "tokens" in user %}
          {%- set a_loop = loop %}
          {%- for token in user["tokens"] %}
rancher_user_token_dir_{{ a_loop.index }}_{{ loop.index }}:
  file.directory:
    - name: /opt/rancher/clusters/{{ pillar["rancher"]["cluster_name"] }}/tokens/{{ user["username"] }}
    - mode: 700
    - makedirs: True

rancher_user_token_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: |
        # Get user just to check user exists
        USER_ID=$(curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" \
          --get --data-urlencode "username={{ user["username"] }}" \
          "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/users" | jq .data | jq -r .[].id | head -n 1)
        if [[ -z ${USER_ID} ]]; then
          echo username not found
          exit 1
        fi
        # Even admin cannot create token for another user, but rancher has public api with auth and one can get temporary bearer token with auth
        # https://forums.rancher.com/t/unable-to-create-api-keys-for-an-user-using-curl/12899/3
        # https://rancher.com/adding-custom-nodes-kubernetes-cluster-rancher-2-0-tech-preview-2
        USER_BEARER_TOKEN=$(curl -sS -X POST -H 'Accept: application/json' -H 'Content-Type: application/json' -d '{
            "username": "{{ user["username"] }}",
            "password": "{{ user["password"] }}",
            "description": "temp salt",
            "ttl": 60000
          }' "https://{{ pillar["rancher"]["cluster_domain"] }}/v3-public/localProviders/local?action=login" | jq -r .token)
        # Check if token with the needed description exist, make new token if not
        TOKEN=$(curl -sS -u "${USER_BEARER_TOKEN}" --get "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/tokens" \
          | jq '.data[] | select(.description == "{{ token["description"] }}")' | jq -r .id | grep -q token- || \
          curl -sS -u "${USER_BEARER_TOKEN}" -X POST -H 'Accept: application/json' -H 'Content-Type: application/json' -d '{
            "description": "{{ token["description"] }}"
          }' "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/tokens" | jq -r .token)
        # Save token to file
        if [[ -z ${TOKEN} ]]; then
          echo token not created and not saved
        else
          echo ${TOKEN} > /opt/rancher/clusters/{{ pillar["rancher"]["cluster_name"] }}/tokens/{{ user["username"] }}/{{ token["description"] }}
          echo token saved to /opt/rancher/clusters/{{ pillar["rancher"]["cluster_name"] }}/tokens/{{ user["username"] }}/{{ token["description"] }}
        fi
          {%- endfor %}
        {%- endif %}
      {%- endfor %}
    {%- endif %}

    {%- if "projects" in pillar["rancher"] %}
      {%- for project in pillar["rancher"]["projects"] %}
rancher_project_{{ loop.index }}:
  cmd.run:
    - name: |
        # Get projects with name and get id of first
        PROJECT_ID=$(curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" \
          --get --data-urlencode "name={{ project["name"] }}" \
          "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/projects" | jq .data | jq -r .[].id | head -n 1)
        if [[ -n ${PROJECT_ID} ]]; then
          # Update project
          curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" -X PUT -H 'Accept: application/json' -H 'Content-Type: application/json' -d '{
            "name": "{{ project["name"] }}",
            "description": "{{ project["description"] }}",
            "state": "active",
            "baseType": "project",
            "clusterId": "local"
          }' "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/projects/${PROJECT_ID}"
        else
          # Create project
          curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" -X POST -H 'Accept: application/json' -H 'Content-Type: application/json' -d '{
            "name": "{{ project["name"] }}",
            "description": "{{ project["description"] }}",
            "state": "active",
            "baseType": "project",
            "clusterId": "local"
          }' "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/projects"
        fi

        {%- if "members" in project and "users" in project["members"] %}
          {%- set a_loop = loop %}
          {%- for member in project["members"]["users"] %}
rancher_project_member_user_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: |
        # Get user and project ids
        USER_ID=$(curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" --get \
            {%- if "username" in member %}
          --data-urlencode "username={{ member["username"] }}" \
            {%- endif %}
            {%- if "name" in member %}
          --data-urlencode "name={{ member["name"] }}" \
            {%- endif %}
          "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/users" | jq .data | jq -r .[].id | head -n 1)
        if [[ -z ${USER_ID} ]]; then
          echo member username not found
          exit 1
        fi
        PROJECT_ID=$(curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" \
          --get --data-urlencode "name={{ project["name"] }}" \
          "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/projects" | jq .data | jq -r .[].id | head -n 1)
        if [[ -z ${PROJECT_ID} ]]; then
          echo member project not found
          exit 1
        fi
            {%- if "name" in member %}
        # Also get google user principal id if exists (needed to give role for Google user)
        USER_PRINCIPLE_ID=$(curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" --get \
          --data-urlencode "name={{ member["name"] }}" \
          "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/users" | jq .data[] | jq -r .principalIds[] | grep googleoauth_user | head -n 1)
        if [[ -z ${USER_PRINCIPLE_ID} ]]; then
          echo member user principle id not found
          exit 1
        fi
            {%- endif %}
        # Get all bindings by user and project to remove - we do not update - remove all and then add needed
        BINDINGS=$(curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" \
          --get --data-urlencode "projectId=${PROJECT_ID}" --data-urlencode "userId=${USER_ID}" \
          "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/projectroletemplatebindings" | jq .data | jq -r .[].id)
        for BINDING in ${BINDINGS}; do
          curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" -X DELETE -H 'Accept: application/json' "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/projectroletemplatebindings/${BINDING}"
        done
        # Create membership
        curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" -X POST -H 'Accept: application/json' -H 'Content-Type: application/json' -d '{
          "projectId": "'${PROJECT_ID}'",
          "roleTemplateId": "{{ member["project_permissions"] }}",
            {%- if "name" in member %}
          "userPrincipalId": "'${USER_PRINCIPLE_ID}'",
            {%- endif %}
          "userId": "'${USER_ID}'"
        }' "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/projectroletemplatebindings"

          {%- endfor %}
        {%- endif %}

        {%- if "members" in project and "groups" in project["members"] %}
          {%- set a_loop = loop %}
          {%- for member in project["members"]["groups"] %}
rancher_project_member_group_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: |
        # Get group and project ids
        # Filter is not working in this API endpoint, use jq filtering
        GROUP_ID=$(curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" \
          --get \
          "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/principals" | jq '.data[] | select(.loginName == "{{ member["groupname"] }}")' | jq -r .id | head -n 1)
        if [[ -z ${GROUP_ID} ]]; then
          echo member groupname not found
          exit 1
        fi
        PROJECT_ID=$(curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" \
          --get --data-urlencode "name={{ project["name"] }}" \
          "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/projects" | jq .data | jq -r .[].id | head -n 1)
        if [[ -z ${PROJECT_ID} ]]; then
          echo member project not found
          exit 1
        fi
        # Get all bindings by user and project to remove - we do not update - remove all and then add needed
        BINDINGS=$(curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" \
          --get --data-urlencode "projectId=${PROJECT_ID}" --data-urlencode "groupPrincipalId=${GROUP_ID}" \
          "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/projectroletemplatebindings" | jq .data | jq -r .[].id)
        for BINDING in ${BINDINGS}; do
          curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" -X DELETE -H 'Accept: application/json' "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/projectroletemplatebindings/${BINDING}"
        done
        # Create membership
        curl -sS -u "{{ pillar["rancher"]["bearer_token"] }}" -X POST -H 'Accept: application/json' -H 'Content-Type: application/json' -d '{
          "projectId": "'${PROJECT_ID}'",
          "roleTemplateId": "{{ member["project_permissions"] }}",
          "groupPrincipalId": "'${GROUP_ID}'"
        }' "https://{{ pillar["rancher"]["cluster_domain"] }}/v3/projectroletemplatebindings"

          {%- endfor %}
        {%- endif %}

      {%- endfor %}
    {%- endif %}

  {%- endif %}
{% endif %}
