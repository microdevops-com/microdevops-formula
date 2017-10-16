{% if (pillar['test'] is defined) and (pillar['test'] is not none) %}
  {%- if (pillar['test']['git_commit'] is defined) and (pillar['test']['git_commit'] is not none) %}
    {%- for git_path in pillar['test']['git_commit'] %}
      {%- set git_result_count = salt['cmd.shell']('cd \'' ~ git_path ~ '\' && git ls-files -d -m -o --exclude-standard | wc -l') %}
      {%- if git_result_count != '0' %}
        {%- set git_result = salt['cmd.shell']('cd \'' ~ git_path ~ '\' && git ls-files -d -m -o --exclude-standard') %}
git_commit_{{ loop.index }}:
  test.configurable_test_state:
    - name: git_commit
    - changes: False
    - result: False
    - comment: 'Git path {{ git_path }} has uncommited changes: {{ git_result }}'
      {%- endif %}
    {%- endfor %}
  {%- endif %}
{% endif %}
