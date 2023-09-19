wazuh_internal_users_yml_with_passwords:
  file.managed:
    - name: "/opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_indexer/internal_users.yml"
    - contents_pillar: wazuh:internal_users

wazuh_convert_internal_users_password_to_hash:
  cmd.run:
    - name: |
        while IFS= read -r line; do
          if [[ "${line}" =~ ^[[:space:]]*password:[[:space:]]\"(.*)\" ]]; then
            password="${BASH_REMATCH[1]}"
            hashed_password=$(docker run --rm {{ pillar['wazuh']['wazuh_indexer']['image'] }} /bin/bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh -p "${password}" | tail -n -1)
            echo "$line" | sed -E "s@^[[:space:]]+password: \"(.*)\"@  hash: \"${hashed_password}\"@"
          else
            echo "$line"
          fi
        done < /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_indexer/internal_users.yml > /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_indexer/internal_users.tmp
        mv /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_indexer/internal_users.tmp /opt/wazuh/{{ pillar["wazuh"]["domain"] }}/single-node/config/wazuh_indexer/internal_users.yml
