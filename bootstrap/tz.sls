{% if pillar["bootstrap"] is defined and "tz" in pillar["bootstrap"] %}
bootstrap_tz:

  {% if grains["oscodename"] == "jessie" %}
  file.managed:
    - name: "/etc/timezone"
    - contents: |
        {{ pillar["bootstrap"]["tz"]["tz"] }}

  cmd.run:
    - name: dpkg-reconfigure -f noninteractive tzdata

  {% else %}
  timezone.system:
    "{{ pillar["bootstrap"]["tz"]["tz"] }}":
      - utc: {{ pillar["bootstrap"]["tz"]["utc"] }}

  {% endif %}

{% endif %}
