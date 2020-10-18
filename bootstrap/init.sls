include:
{% if grains['oscodename'] == 'bionic' %}
  - .bionic
{% endif %}
{% if grains['oscodename'] == 'focal' %}
  - .focal
{% endif %}
