  {%- if "pkg" in pillar["app"] %}
  # Just install existing package to refresh db
app_pkg_refresh:
  pkg.installed:
    - refresh: True
    - pkgs:
      - nano

    {%- for pkg, version in pillar["app"]["pkg"].items() %}
app_pkg_{{ loop.index }}:
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
