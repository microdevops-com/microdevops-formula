{% if pillar["_errors"] is defined %}
app_case_pillar_render_errors:
  test.configurable_test_state:
    - name: nothing_done
    - changes: False
    - result: False
    - comment: |
        ERROR: There are pillar errors, so nothing has been done.
        {{ pillar["_errors"] | json() }}

include:
  - .deploy
