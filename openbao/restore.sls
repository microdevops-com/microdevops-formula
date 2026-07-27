{% if pillar["openbao"] is defined and pillar["openbao"].get("restore") %}

{% set restore_cfg = pillar["openbao"]["restore"] %}
{% set snapshot_path = restore_cfg.get("snapshot_path") %}
{% set postgres_cfg = pillar["openbao"].get("postgresql", {}) %}
{% set postgresql_database = postgres_cfg.get("database", "openbao") %}
{% set postgresql_user = postgres_cfg.get("user", "openbao") %}

openbao_restore_pillar_missing:
  cmd.run:
    - name: |
        echo "ERROR: openbao.restore requires openbao.restore.snapshot_path"
        exit 1
    - onlyif: test -z "{{ snapshot_path }}"

{% if snapshot_path %}
openbao_restore_stop:
  service.dead:
    - name: openbao

openbao_restore_drop_database:
  cmd.run:
    - name: |
        su - postgres -c "psql -d postgres -c \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='{{ postgresql_database }}';\""
        su - postgres -c "dropdb --if-exists {{ postgresql_database }}"
    - shell: /bin/bash
    - require:
      - service: openbao_restore_stop

openbao_restore_create_database:
  cmd.run:
    - name: su - postgres -c "createdb -O {{ postgresql_user }} {{ postgresql_database }}"
    - require:
      - cmd: openbao_restore_drop_database

openbao_restore_load_database:
  cmd.run:
    - name: su - postgres -c "psql {{ postgresql_database }}" < {{ snapshot_path }}
    - shell: /bin/bash
    - require:
      - cmd: openbao_restore_create_database

openbao_restore_start:
  service.running:
    - name: openbao
    - enable: true
    - require:
      - cmd: openbao_restore_load_database
{% endif %}

{% endif %}
