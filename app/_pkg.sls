  {%- if "pkg" in pillar["app"] %}
  # Just install existing package to refresh db
  # For app.mini, app.deploy this will be duplicated for ean app type, that's a workaround
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
