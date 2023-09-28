  {%- if "pkg" in pillar["app"] %}
  # For app.mini, app.deploy this will be duplicated for each defined app type

  # Just install existing package to refresh db
app_{{ app_type }}_pkg_refresh:
  pkg.installed:
    - refresh: True
    - pkgs:
      - nano

    {%- for pkg, version in pillar["app"]["pkg"].items() %}
app_{{ app_type }}_pkg_{{ loop.index }}:
      {%- if version == "latest" %}
  pkg.latest:
    - pkgs:
      - {{ pkg }}
      {%- elif version == "any" %}
  pkg.installed:
    - pkgs:
      - {{ pkg }}
      {%- else %}
  pkg.installed:
    - pkgs:
      - {{ pkg }}: '{{ version }}*'
      {%- endif %}

    {%- endfor %}
  {%- endif %}
