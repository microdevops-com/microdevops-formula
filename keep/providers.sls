{% if pillar["keep"] is defined and pillar["acme"] is defined and pillar["keep"]["api_key"] is defined %}

create_health_check_script:
  file.managed:
    - name: {{ pillar["keep"]["homedir"] }}/health_check.sh
    - mode: '0755'
    - contents: |
        #!/bin/bash
        MAX_ATTEMPTS={{ pillar["keep"].get("health_retries", 30) }}
        DELAY={{ pillar["keep"].get("health_retry_delay", 5) }}
        API_URL="https://{{ pillar["keep"]["host"] }}:8443"

        echo "Checking Keep health status..."
        for ((i=1; i<=$MAX_ATTEMPTS; i++)); do
          # Try official health endpoint
          response=$(curl -s -k -o /dev/null -w "%{http_code}" $API_URL/healthcheck 2>/dev/null || echo "000")

          if [ "$response" = "200" ]; then
            echo "Health check passed after $i attempts!"
            exit 0
          fi

          # Also try API endpoint as a backup check
          alt_response=$(curl -s -k -o /dev/null -w "%{http_code}" $API_URL/api/healthcheck 2>/dev/null || echo "000")
          if [ "$alt_response" = "200" ]; then
            echo "API health check passed after $i attempts!"
            exit 0
          fi

          echo "Attempt $i/$MAX_ATTEMPTS: Keep is not ready yet (status: $response). Waiting ${DELAY}s..."
          sleep $DELAY
        done

        echo "Keep service did not become healthy after $MAX_ATTEMPTS attempts"
        exit 1

run_health_check:
  cmd.run:
    - name: {{ pillar["keep"]["homedir"] }}/health_check.sh
    - require:
      - file: create_health_check_script

create_api_key_file:
  file.managed:
    - name: {{ pillar["keep"]["homedir"] }}/state/keep-salt-managed
    - contents: {{ pillar["keep"]["api_key"] }}
    - makedirs: True
    - user: 999
    - group: 999
    - require:
        - cmd: run_health_check

{% if "mysql_host" in pillar["keep"] and "dbport" in pillar["keep"] and "dbusername" in pillar["keep"] and "dbpassword" in pillar["keep"] and "dbname" in pillar["keep"] and "default_username" in pillar["keep"] %}
add_api_key_to_database:
  cmd.run:
    - name: |
        API_KEY="{{ pillar["keep"]["api_key"] }}"
        REFERENCE_ID="salt-managed"
        TENANT_ID="keep"
        KEY_HASH=$(echo -n "$API_KEY" | sha256sum | awk '{print $1}')

        mysql -h {{ pillar["keep"]["mysql_host"] }} \
              -P {{ pillar["keep"]["dbport"] }} \
              -u {{ pillar["keep"]["dbusername"] }} \
              -p{{ pillar["keep"]["dbpassword"] }} \
              {{ pillar["keep"]["dbname"] }} \
              -e "DELETE FROM tenantapikey WHERE reference_id='${REFERENCE_ID}' AND tenant_id='${TENANT_ID}'"

        mysql -h {{ pillar["keep"]["mysql_host"] }} \
              -P {{ pillar["keep"]["dbport"] }} \
              -u {{ pillar["keep"]["dbusername"] }} \
              -p{{ pillar["keep"]["dbpassword"] }} \
              {{ pillar["keep"]["dbname"] }} \
              -e "DELETE FROM tenantapikey WHERE key_hash='${KEY_HASH}'"

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
        - cmd: run_health_check
{% endif %}

{% if "postgresql_host" in pillar["keep"] and "dbport" in pillar["keep"] and "dbusername" in pillar["keep"] and "dbpassword" in pillar["keep"] and "dbname" in pillar["keep"] and "default_username" in pillar["keep"] %}
add_api_key_to_postgresql:
  cmd.run:
    - name: |
        API_KEY="{{ pillar["keep"]["api_key"] }}"
        REFERENCE_ID="salt-managed"
        TENANT_ID="keep"
        KEY_HASH=$(echo -n "$API_KEY" | sha256sum | awk '{print $1}')
        
        PGPASSWORD="{{ pillar["keep"]["dbpassword"] }}" psql -h {{ pillar["keep"]["postgresql_host"] }} \
              -p {{ pillar["keep"]["dbport"] }} \
              -U {{ pillar["keep"]["dbusername"] }} \
              -d {{ pillar["keep"]["dbname"] }} \
              -c "DELETE FROM tenantapikey WHERE reference_id='${REFERENCE_ID}' AND tenant_id='${TENANT_ID}'"

        PGPASSWORD="{{ pillar["keep"]["dbpassword"] }}" psql -h {{ pillar["keep"]["postgresql_host"] }} \
              -p {{ pillar["keep"]["dbport"] }} \
              -U {{ pillar["keep"]["dbusername"] }} \
              -d {{ pillar["keep"]["dbname"] }} \
              -c "DELETE FROM tenantapikey WHERE key_hash='${KEY_HASH}'"

        PGPASSWORD="{{ pillar["keep"]["dbpassword"] }}" psql -h {{ pillar["keep"]["postgresql_host"] }} \
              -p {{ pillar["keep"]["dbport"] }} \
              -U {{ pillar["keep"]["dbusername"] }} \
              -d {{ pillar["keep"]["dbname"] }} \
              -c "INSERT INTO tenantapikey 
                  (tenant_id, reference_id, key_hash, is_system, is_deleted, system_description, created_by, role, created_at) 
                  VALUES 
                  ('${TENANT_ID}', '${REFERENCE_ID}', '${KEY_HASH}', false, false, 'Created by Salt', '{{ pillar["keep"]["default_username"] }}', 'admin', NOW())"
    - require:
        - file: create_api_key_file
        - cmd: run_health_check
{% endif %}

{% if "sqlite_path" in pillar["keep"] and "default_username" in pillar["keep"] %}
add_api_key_to_sqlite:
  cmd.run:
    - name: |
        API_KEY="{{ pillar["keep"]["api_key"] }}"
        REFERENCE_ID="salt-managed"
        TENANT_ID="keep"
        KEY_HASH=$(echo -n "$API_KEY" | sha256sum | awk '{print $1}')
        DB_PATH="{{ pillar["keep"]["sqlite_path"] }}"

        # Check if tenantapikey table exists, skip if it doesn't
        TABLE_EXISTS=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='tenantapikey'")
        if [ "$TABLE_EXISTS" -eq "0" ]; then
          echo "Table 'tenantapikey' does not exist in the database. Skipping operations."
          exit 0
        fi
        sqlite3 "$DB_PATH" "DELETE FROM tenantapikey WHERE reference_id='${REFERENCE_ID}' AND tenant_id='${TENANT_ID}'"      
        sqlite3 "$DB_PATH" "DELETE FROM tenantapikey WHERE key_hash='${KEY_HASH}'"
        sqlite3 "$DB_PATH" "INSERT INTO tenantapikey 
                (tenant_id, reference_id, key_hash, is_system, is_deleted, system_description, created_by, role, created_at) 
                VALUES 
                ('${TENANT_ID}', '${REFERENCE_ID}', '${KEY_HASH}', 0, 0, 'Created by Salt', '{{ pillar["keep"]["default_username"] }}', 'admin', datetime('now'))"
    - require:
        - file: create_api_key_file
        - cmd: run_health_check
    - onlyif: test -f {{ pillar["keep"]["sqlite_path"] }}
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
      - cmd: run_health_check
    {% endfor %}
  {% endif %}
{% endif %}
