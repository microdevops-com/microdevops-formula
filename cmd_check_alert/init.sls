include:
{% if grains["oscodename"] in ["noble", "trixie"] %}
  - .sensu-plugins_via_gem
{% else %}
  - .sensu-plugins
{% endif %}
  - .cmd_check_alert
