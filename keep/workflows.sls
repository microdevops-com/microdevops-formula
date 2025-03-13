{% if "workflows" in pillar["keep"] %}

# Create workflows directory
create_workflows_directory:
  file.directory:
    - name: {{ pillar["keep"]["homedir"] }}/workflows
    - makedirs: True

# Create backup of existing workflows
backup_workflows:
  cmd.run:
    - name: |
        if [ -d {{ pillar["keep"]["homedir"] }}/workflows ] && [ "$(ls -A {{ pillar["keep"]["homedir"] }}/workflows)" ]; then
          timestamp=$(date +%Y%m%d_%H%M%S)
          mkdir -p {{ pillar["keep"]["homedir"] }}/workflows_backup
          cp -r {{ pillar["keep"]["homedir"] }}/workflows {{ pillar["keep"]["homedir"] }}/workflows_backup/workflows_$timestamp
          echo "Workflows backed up to {{ pillar["keep"]["homedir"] }}/workflows_backup/workflows_$timestamp"
        else
          echo "No workflows to back up"
        fi
    - require:
      - file: create_workflows_directory

# Clean up workflows directory
clean_workflows_directory:
  cmd.run:
    - name: |
        rm -f {{ pillar["keep"]["homedir"] }}/workflows/*.yaml
        echo "Removed old workflow files"
    - require:
      - cmd: backup_workflows

# Create check_and_connect_workflow script
create_check_and_connect_workflow_script:
  file.managed:
    - name: {{ pillar["keep"]["homedir"] }}/check_and_connect_workflow.sh
    - mode: '0755'
    - contents: |
        #!/bin/bash
        #set -x
        retries=$1
        for ((i=1; i<=retries; i++)); do
          # Run the workflow apply command
          {% if pillar["keep"].get("full_sync_workflows", false) %}
          output=$(keep workflow apply --file /workflows --full-sync 2>&1)
          {% else %}
          output=$(keep workflow apply --file /workflows 2>&1)
          {% endif %}
          
          exit_code=$?
          
          # Check for successful execution
          if [ $exit_code -eq 0 ]; then
            echo "Successfully applied workflows"
            exit 0
          fi
          
          # Check for connection errors
          if echo "$output" | grep -q "IncompleteRead" || echo "$output" | grep -q "ConnectionError"; then
            if [ $i -lt $retries ]; then
              echo "Connection error. Retrying ($i/$retries)"
              sleep 2
              continue
            fi
          fi
          
          # If we reached here on the last attempt, we failed
          if [ $i -eq $retries ]; then
            echo "Failed to apply workflows after $retries attempts"
            echo "Error: $output"
            exit 1
          fi
          
          # Other errors, retry with delay
          echo "Error applying workflows. Retrying in 3 seconds... ($i/$retries)"
          echo "Error: $output"
          sleep 1
        done

{% set max_retries = pillar["keep"].get("retries", 3) %}
{% for workflow in pillar["keep"]["workflows"] %}
workflow_file_{{ loop.index }}:
  file.managed:
    - name: {{ pillar["keep"]["homedir"] }}/workflows/workflow_{{ loop.index }}.yaml
    - contents: |
        {{ workflow | indent(8) }}
    - makedirs: True
    - require:
      - cmd: clean_workflows_directory
{% endfor %}

# Apply all workflows at once
apply_all_workflows:
  docker_container.run:
    - name: keep-apply-workflows
    - image: us-central1-docker.pkg.dev/keephq/keep/keep-cli
    - binds:
      - {{ pillar["keep"]["homedir"] }}/workflows:/workflows
      - {{ pillar["keep"]["homedir"] }}/.env:/venv/lib/python3.11/site-packages/keep/.env
      - {{ pillar["keep"]["homedir"] }}/check_and_connect_workflow.sh:/check_and_connect_workflow.sh
    - environment:
      - KEEP_API_URL: https://{{ pillar["keep"]["host"] }}:8443
      - KEEP_API_KEY: {{ pillar["keep"]["api_key"] }}
    - command: /check_and_connect_workflow.sh {{ max_retries }}
    - auto_remove: True
    - force: True
    - require:
      - file: create_check_and_connect_workflow_script
      {% for workflow in pillar["keep"]["workflows"] %}
      - file: workflow_file_{{ loop.index }}
      {% endfor %}
{% endif %}
