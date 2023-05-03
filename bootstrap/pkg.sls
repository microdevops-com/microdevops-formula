{% if pillar["bootstrap"] is defined and "pkg" in pillar["bootstrap"] %}
  {%- if "installed" in pillar["bootstrap"]["pkg"] %}
bootstrap_pkg_install:

    {% for key, value in pillar["bootstrap"]["pkg"]["installed"] %}
      {% if value == "latest" %}
  pkg.latest:
    - refresh: True
    - pkgs: {{ package }}
      {% else %}

