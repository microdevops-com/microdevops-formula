{% if grains['os'] == "Windows" %}
unix_nothing_to_do:
  test.configurable_test_state:
    - name: unix_nothing_to_do_info
    - changes: False
    - result: True
    - comment: |
         NOTICE: unix is not for Windows, doing nothing.

{% else %}
include:
  - users
  - users.sudo
{% endif %}
