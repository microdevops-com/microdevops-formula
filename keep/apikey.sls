{% if pillar["keep"] is defined and pillar["keep"]["api_key"] is defined %}

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

{% endif %}
