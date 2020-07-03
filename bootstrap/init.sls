include:
{% if grains['oscodename'] == 'focal' %}
  - bootstrap.focal
{% endif %}
