{% if pillar["keep"] is defined and pillar["acme"] is defined and pillar["keep"]["api_key"] is defined %}

create_api_key_file:
  file.managed:
    - name: {{ pillar["keep"]["homedir"] }}/state/keep-salt-managed
    - contents: {{ pillar["keep"]["api_key"] }}
    - makedirs: True
    - user: 999
    - group: 999

{% if "mysql_host" in pillar["keep"] and "dbport" in pillar["keep"] and "dbusername" in pillar["keep"] and "dbpassword" in pillar["keep"] and "dbname" in pillar["keep"] and "default_username" in pillar["keep"] %}
add_api_key_to_database:
  cmd.run:
    - name: |
        API_KEY="{{ pillar["keep"]["api_key"] }}"
        REFERENCE_ID="salt-managed"
        TENANT_ID="keep"
        KEY_HASH=$(echo -n "$API_KEY" | sha256sum | awk '{print $1}')
        
        # Видалення старого ключа, якщо він існує
        mysql -h {{ pillar["keep"]["mysql_host"] }} \
              -P {{ pillar["keep"]["dbport"] }} \
              -u {{ pillar["keep"]["dbusername"] }} \
              -p{{ pillar["keep"]["dbpassword"] }} \
              {{ pillar["keep"]["dbname"] }} \
              -e "DELETE FROM tenantapikey WHERE reference_id='${REFERENCE_ID}' AND tenant_id='${TENANT_ID}'"
        
        # Додавання нового ключа
        mysql -h {{ pillar["keep"]["mysql_host"] }} \
              -P {{ pillar["keep"]["dbport"] }} \
              -u {{ pillar["keep"]["dbusername"] }} \
              -p{{ pillar["keep"]["dbpassword"] }} \
              {{ pillar["keep"]["dbname"] }} \
              -e "INSERT INTO tenantapikey 
                  (tenant_id, reference_id, key_hash, is_system, is_deleted, system_description, created_by, role, created_at) 
                  VALUES 
                  ('${TENANT_ID}', '${REFERENCE_ID}', '${KEY_HASH}', 0, 0, 'Created by Salt', '{{ pillar["keep"]["default_username"] }}', 'admin', NOW())"
    - require:
        - file: create_api_key_file
{% endif %}

create_check_and_connect_script:
  file.managed:
    - name: {{ pillar["keep"]["homedir"] }}/check_and_connect.sh
    - mode: '0755'
    - contents: |
        #!/bin/bash
        #set -x
        provider_type=$1
        provider_name=$2
        force=$3
        retries=$4
        shift 4
        provider_args="$@"
        
        # Check if provider exists
        echo
        echo "Checking if provider $provider_name exists..."
        echo
        provider_exists=0
        provider_id=""
        
        for ((i=1; i<=retries; i++)); do
          # Run the command and capture both output and exit status
          output=$(keep provider list 2>&1)
          exit_code=$?
          
          # Check for connection errors (non-zero exit code or specific error message)
          if [ $exit_code -ne 0 ] || echo "$output" | grep -q "IncompleteRead"; then
            if [ $i -lt $retries ]; then
              echo
              echo "Connection error. Retrying ($i/$retries)"
              echo
              sleep 1
              continue
            else
              echo
              echo "Command failed after $retries attempts"
              echo
              exit 1
            fi
          fi

          # If we got here, the command succeeded - now check if provider exists
          if echo "$output" | grep -q "$provider_name"; then
            provider_id=$(echo "$output" | grep -E "\|\s+$provider_name\s+\|" | awk '{print $2}' | tr -d ' ')
            if [ ! -z "$provider_id" ]; then
              provider_exists=1
              echo
              echo "Provider $provider_name exists with ID $provider_id"
              echo
            fi
          else
            echo
            echo "Provider $provider_name not found in the list"
            echo
          fi
          # No need to retry if command was successful, even if provider wasn't found
          break
        done
        
        # If provider exists and force is true, remove it
        echo
        echo "Provider exists: $provider_exists, Force update: $force"
        echo
        if [ $provider_exists -eq 1 ] && ([ "$force" = "true" ] || [ "$force" = "True" ] || [ "$force" = "TRUE" ]); then
          echo
          echo "Provider $provider_name exists and force update is true, removing..."
          echo
          for ((i=1; i<=retries; i++)); do
            output=$(keep provider delete $provider_id 2>&1)
            exit_code=$?
            
            if [ $exit_code -eq 0 ]; then
              provider_exists=0
              echo
              echo "Successfully deleted provider $provider_name with ID $provider_id"
              echo
              break
            fi
            
            # Check for connection errors
            if [ $i -lt $retries ]; then
              echo
              echo "Failed to delete provider. Retrying ($i/$retries)"
              echo
              sleep 1
            else
              echo
              echo "Failed to delete provider after $retries attempts"
              echo
              exit 1
            fi
          done
        fi
        
        # If provider doesn't exist, connect it
        if [ $provider_exists -eq 0 ]; then
          echo
          echo "Connecting provider $provider_name..."
          echo
          for ((i=1; i<=retries; i++)); do
            output=$(keep provider connect $provider_type --provider-name "$provider_name" $provider_args 2>&1)
            exit_code=$?
            
            if [ $exit_code -eq 0 ]; then
              echo
              echo "Successfully connected provider $provider_name"
              echo
              break
            fi
            
            # Check for connection errors
            if [ $i -lt $retries ]; then
              echo
              echo "Failed to connect provider. Retrying ($i/$retries)"
              echo
              sleep 1
            else
              echo
              echo "Failed to connect provider after $retries attempts"
              echo
              exit 1
            fi
          done
        else
          echo
          echo "Provider $provider_name already exists and force is not true, skipping connection."
          echo
        fi

keep-cli_image:
  cmd.run:
    - name: docker pull us-central1-docker.pkg.dev/keephq/keep/keep-cli

env_file:
  file.touch:
    - name: {{ pillar["keep"]["homedir"] }}/.env

  {% if 'providers' in pillar["keep"] %}
    {% set max_retries = pillar["keep"].get("retries", 3) %}
    {% for provider in pillar["keep"]["providers"] %}
connecting {{ provider["type"] }} provider named {{ provider["name"] }}:
  docker_container.run:
    - name: connecting-{{ provider["type"] }}-provider-named-{{ provider["name"] }}
    - image: us-central1-docker.pkg.dev/keephq/keep/keep-cli
    - binds:
      - {{ pillar["keep"]["homedir"] }}/.env:/venv/lib/python3.11/site-packages/keep/.env
      - {{ pillar["keep"]["homedir"] }}/check_and_connect.sh:/check_and_connect.sh
    - environment:
      - KEEP_API_URL: https://{{ pillar["keep"]["host"] }}:8443
      - KEEP_API_KEY: {{ pillar["keep"]["api_key"] }}
    - command: /check_and_connect.sh "{{ provider["type"] }}" "{{ provider["name"] }}" "{{ provider["force"] | default(False) }}" "{{ max_retries }}" {{ provider["args"] | join(" ") }}
    - auto_remove: True
    - force: True
    - require:
      - file: create_check_and_connect_script
    {% endfor %}
  {% endif %}
{% endif %}
