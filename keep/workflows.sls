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

# Clean workflows directory
clean_workflows_directory:
  cmd.run:
    - name: |
        rm -f {{ pillar["keep"]["homedir"] }}/workflows/*.yaml
        echo "Removed old workflow files"
    - require:
      - cmd: backup_workflows


# Generate workflow files
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

# Apply workflows
apply_workflows:
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
    - command: keep workflow apply --file /workflows --full-sync
    - auto_remove: True
    - force: True
    - require:
      {% for workflow in pillar["keep"]["workflows"] %}
      - file: workflow_file_{{ loop.index }}
      {% endfor %}
{% endif %}
