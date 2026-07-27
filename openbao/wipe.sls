{% if pillar["openbao"] is defined %}

{% set config_dir = pillar["openbao"].get("config_dir", "/etc/openbao") %}
{% set data_dir = pillar["openbao"].get("data_dir", "/opt/openbao/data") %}
{% set default_paths = [data_dir, "/opt/openbao/snapshots"] %}
{% set wipe_paths = pillar["openbao"].get("wipe", {}).get("paths", default_paths) %}

openbao_wipe_stop:
  service.dead:
    - name: openbao

{% for p in wipe_paths %}
openbao_remove_path_{{ loop.index }}:
  cmd.run:
    - name: rm -rf {{ p }}
    - onlyif: test -e {{ p }}
    - require:
      - service: openbao_wipe_stop
{% endfor %}

openbao_purge_package:
  pkg.purged:
    - name: openbao
    - require:
      - service: openbao_wipe_stop

include:
  - openbao.init
  - openbao.initialization

{% endif %}
