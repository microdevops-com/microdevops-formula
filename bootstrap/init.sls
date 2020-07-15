include:
{% if grains['oscodename'] == 'bionic' %}
  - bootstrap.bionic
{% endif %}
{% if grains['oscodename'] == 'focal' %}
  - bootstrap.focal
{% endif %}
