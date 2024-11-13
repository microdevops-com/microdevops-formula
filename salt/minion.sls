{% if pillar["salt"] is defined and "minion" in pillar["salt"] %}

  {%- for host in pillar["salt"]["minion"]["hosts"] %}
salt_master_hosts_{{ loop.index }}:
  host.present:
    - clean: True
    - ip: {{ host["ip"] }}
    - names:
        - {{ host["name"] }}
  {%- endfor %}

  {%- if grains["os"] in ["Windows"] %}
include:
  - .minion_windows
  {%- elif grains["os"] in ["Ubuntu", "Debian"] and pillar["salt"]["minion"]["version"]|int in [3006, 3007] %}
include:
  - .minion_linux_onedir
  {%- endif %}

{% else %}
salt_minion_nothing_done_info:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: True
    - comment: |
        INFO: This state was not configured, so nothing has been done. But it is OK.

{% endif %}
