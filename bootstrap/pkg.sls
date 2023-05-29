{%- if pillar["bootstrap"] is defined and "pkg" in pillar["bootstrap"] %}
  {%- with %}
    {%- set pkgs_list_version = [] %}
    {%- set pkgs_list_latest = [] %}
    {%- for name, version in pillar["bootstrap"]["pkg"]["installed"].get("pkgs",{}).items() %}
      {%- if version == "latest" %}
        {%- do pkgs_list_latest.append(name) %}
      {%- elif version == "any" %}
        {%- do pkgs_list_version.append(name) %}
      {%- else %}
        {%- do pkgs_list_version.append({name : version}) %}
      {%- endif %}
    {%- endfor %}

    {%- if pkgs_list_version %}
bootstrap_pkg_installed_pkgs_version:
  pkg.installed:
    - pkgs: {{ pkgs_list_version }}
    {%- endif %}

    {%- if pkgs_list_latest %}
bootstrap_pkg_installed_pkgs_latest:
  pkg.installed:
    - pkgs: {{ pkgs_list_latest }}
    {%- endif %}
  {%- endwith %}

  {%- with %}
    {%- set pkgs_list = [] %}
    {%- for name, source in pillar["bootstrap"]["pkg"]["installed"].get("sources",{}).items() %}
      {%- do pkgs_list.append({name: source}) %}
    {%- endfor %}
    {%- if pkgs_list %}
bootstrap_pkg_installed_sources:
  pkg.installed:
    - sources: {{ pkgs_list }}
    {%- endif %}
  {%- endwith %}
{%- endif %}
