{%- if pillar["freeipa"]["dsconf"] is defined %}
  {%- for attribute_name, attribute_value in pillar["freeipa"]["dsconf"]["attributes"].items() %}
setting the {{ attribute_name }} attribute:
  cmd.run:
    - shell: /bin/bash
    - name: docker exec freeipa-{{ pillar["freeipa"]["hostname"] }} bash -c "dsconf {{ pillar['freeipa']['dsconf']['instance'] }} config replace {{ attribute_name }}={{ attribute_value }}"
  {%- endfor %}
{%- endif %}
