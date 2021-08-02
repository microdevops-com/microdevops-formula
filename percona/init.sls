{%-    if pillar['percona'] is defined and
          pillar['percona'] is not none
%}
include:
    {%-    if pillar['percona']['databases'] is defined and
              pillar['percona']['databases'] is not none and
              pillar['percona']['databases'] is mapping
    %}
  - .next
    {%- elif  pillar['percona']['databases'] is defined and
              pillar['percona']['databases'] is not none and
              pillar['percona']['databases'] is iterable and
              pillar['percona']['databases'] is not string and
              pillar['percona']['databases'] is not mapping
    %}
  - .percona
    {%- endif %}
{%- endif %}

