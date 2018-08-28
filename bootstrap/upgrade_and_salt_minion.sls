{%- if grains['oscodename'] == 'xenial' %}
bootstrap_salt_minion_1:
  cmd.script:
    - source: salt://bootstrap/scripts/xenial_upgrade_and_salt_minion.sh
    - env:
      - SALT_MASTER_NAME: '{{ pillar["salt_master_name"] }}'
      - SALT_MASTER_IP: '{{ pillar["salt_master_ip"] }}'
{% endif %}

{%- if grains['oscodename'] == 'stretch' %}
bootstrap_salt_minion_1:
  cmd.script:
    - source: salt://bootstrap/scripts/stretch_upgrade_and_salt_minion.sh
    - env:
      - SALT_MASTER_NAME: '{{ pillar["salt_master_name"] }}'
      - SALT_MASTER_IP: '{{ pillar["salt_master_ip"] }}'
{% endif %}
