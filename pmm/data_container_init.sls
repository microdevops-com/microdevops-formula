pmm_data_container:
  docker_container.running:
    - name: percona-{{ pillar["pmm"]["name"] }}-data
    - user: root
    - image: {{ pillar["pmm"]["image"] }}
    - detach: True
    - volumes:
      - /srv
    - command: /bin/true
    - start: False
