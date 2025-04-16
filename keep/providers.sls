{% if pillar["keep"] is defined and pillar["acme"] is defined and pillar["keep"]["api_key"] is defined %}

keep_provider_connect_script:
  file.managed:
    - name: {{ pillar["keep"]["homedir"] }}/keep_provider_connect.sh
    - mode: '0755'
    - contents: |
        #!/bin/bash
        #set -x
        provider_type=$1
        provider_name=$2
        force=$3
        shift 3
        provider_args="$@"
        provider_exists=0
        provider_id=""
        output=$(keep provider list 2>&1)

        echo; echo "Checking if provider $provider_name exists..."; echo; 
        if echo "$output" | grep -q "$provider_name"; then
          provider_exists=1
          provider_id=$(echo "$output" | grep -E "\|\s+$provider_name\s+\|" | awk '{print $2}' | tr -d ' ')
          if [ "$force" = "true" ] || [ "$force" = "True" ] || [ "$force" = "TRUE" ]; then
            echo; echo "Provider $provider_name exists and force update is true, removing..."; echo;
            output=$(keep provider delete $provider_id 2>&1)
            if [ $? -eq 0 ]; then
              provider_exists=0
              echo; echo "Successfully deleted provider $provider_name with ID $provider_id"; echo;
            fi
          else
            echo; echo "Provider $provider_name already exists and force is not true, skipping reconnect."; echo;
          fi
        else
          echo; echo "Provider $provider_name not found in the list"; echo;
        fi

        if [ $provider_exists -eq 0 ]; then
          echo; echo "Connecting provider $provider_name..."; echo;
            output=$(keep provider connect $provider_type --provider-name "$provider_name" $provider_args 2>&1)
            if [ $? -eq 0 ]; then
              echo; echo "Successfully connected provider $provider_name"; echo;
            fi
        fi

keep-cli_image:
  cmd.run:
    - name: docker pull us-central1-docker.pkg.dev/keephq/keep/keep-cli

env_file:
  file.touch:
    - name: {{ pillar["keep"]["homedir"] }}/.env

  {% if 'providers' in pillar["keep"] %}

    {% for provider in pillar["keep"]["providers"] %}
connecting {{ provider["type"] }} provider named {{ provider["name"] }}:
  docker_container.run:
    - name: connecting-{{ provider["type"] }}-provider-named-{{ provider["name"] }}
    - image: us-central1-docker.pkg.dev/keephq/keep/keep-cli
    - binds:
      - {{ pillar["keep"]["homedir"] }}/.env:/venv/lib/python3.11/site-packages/keep/.env
      - {{ pillar["keep"]["homedir"] }}/keep_provider_connect.sh:/keep_provider_connect.sh
    - environment:
      - KEEP_API_URL: https://{{ pillar["keep"]["host"] }}:8443
      - KEEP_API_KEY: {{ pillar["keep"]["api_key"] }}
    - command: /keep_provider_connect.sh "{{ provider["type"] }}" "{{ provider["name"] }}" "{{ provider["force"] | default(False) }}" {{ provider["args"] | join(" ") }}
    - auto_remove: True
    - force: True
    - require:
      - file: keep_provider_connect_script
    {% endfor %}
  {% endif %}
{% endif %}
