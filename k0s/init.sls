{%- set role = salt['pillar.get']('k0s:role', 'single') %}

include:
  - k0s.install
{%- if role == 'controller' %}
  - k0s.config
  - k0s.controller
{%- elif role == 'worker' %}
  - k0s.worker
{%- elif role == 'single' %}
  - k0s.config
  - k0s.controller
{%- endif %}
  - k0s.service
  - k0s.manifest