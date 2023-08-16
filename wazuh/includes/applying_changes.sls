applying_changes:
  cmd.run:
    - name: 'sleep 30; docker exec -t wazuh.indexer bash -c "export JAVA_HOME=/usr/share/wazuh-indexer/jdk && bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh -cd /usr/share/wazuh-indexer/opensearch-security/ -nhnv -cacert /usr/share/wazuh-indexer/certs/root-ca.pem -cert /usr/share/wazuh-indexer/certs/admin.pem -key /usr/share/wazuh-indexer/certs/admin-key.pem -p 9200 -icl"'
    - require:
      - docker_container: wazuh.indexer
