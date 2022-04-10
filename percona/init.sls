{% if pillar["percona"] is defined and "databases" in pillar["percona"] and pillar["percona"]["databases"] is not mapping %}
include:
  - .percona

{% else %}
include:
  - .next

{%- endif %}
