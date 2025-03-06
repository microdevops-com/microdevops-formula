{% if pillar["keep"] is defined and pillar["keep"]["api_key"] is defined %}

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
          output=$(keep provider list)
          if [ $? -eq 0 ]; then
            # Extract the ID if the provider exists
            provider_id=$(echo "$output" | grep -E "\|\s+$provider_name\s+\|" | awk '{print $2}' | tr -d ' ')
            if [ ! -z "$provider_id" ]; then
              provider_exists=1
              echo
              echo "Provider $provider_name exists with ID $provider_id"
              echo
              break
            fi
          fi
          if [ $i -lt $retries ]; then
            echo
            echo "Provider list failed or provider not found. Retrying ($i/$retries)"
            echo
            sleep 1
          else
            echo
            echo "Provider list failed after $retries attempts"
            echo
          fi
        done
        
        # If provider exists and force is true, remove it
        echo
        echo "Provider exists: $provider_exists, Force update: $force"
        echo
        if [ $provider_exists -eq 1 ] && [ "$force" = "true" ] || [ "$force" = "True" ] || [ "$force" = "TRUE" ]; then
          echo
          echo "Provider $provider_name exists and force update is true, removing..."
          echo
          for ((i=1; i<=retries; i++)); do
            if keep provider delete $provider_id; then
              provider_exists=0
              echo
              echo "Successfully deleted provider $provider_name with ID $provider_id"
              echo
              break
            fi
            if [ $i -lt $retries ]; then
              echo
              echo "Failed to delete provider. Retrying ($i/$retries)"
              echo
              sleep 1
            else
              echo
              echo "Failed to delete provider after $retries attempts"
              echo
            fi
          done
        fi
        
        # If provider doesn't exist, connect it
        if [ $provider_exists -eq 0 ]; then
          echo
          echo "Connecting provider $provider_name..."
          echo
          for ((i=1; i<=retries; i++)); do
            if keep provider connect $provider_type --provider-name "$provider_name" $provider_args; then
              echo
              echo "Successfully connected provider $provider_name"
              echo
              break
            fi
            if [ $i -lt $retries ]; then
              echo
              echo "Failed to connect provider. Retrying ($i/$retries)"
              echo
              sleep 1
            else
              echo
              echo "Failed to connect provider after $retries attempts"
              echo
            fi
          done
        else
          echo
          echo "Provider $provider_name already exists, skipping connection."
          echo
        fi

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
{% endif %}:
