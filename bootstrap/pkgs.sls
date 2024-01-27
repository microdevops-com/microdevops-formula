{%- if pillar["bootstrap"] is defined %}
    {%- set pkgs_list_version = [] %} # version + any
    {%- set pkgs_list_latest = [] %}
    {%- set pkgs_list_sources = [] %}

    {%- set pkgs = pillar["bootstrap"].get("pkgs",{}) %}

    {%- do pkgs.update(pillar["bootstrap"].get("pkg",{}).get("installed",{}).get("sources",{})) %} # legacy pillar compat
    {%- do pkgs.update(pillar["bootstrap"].get("pkg",{}).get("installed",{}).get("pkgs",{})) %} # legacy pillar compat

    {%- for name, value in pkgs.items() %}

      {%- if value == "latest" %}
        {%- do pkgs_list_latest.append(name) %}

      {%- elif value == "any" %}
        {%- do pkgs_list_version.append(name) %}

      {%- elif value.startswith("/") or "://" in value %}
        {%- do pkgs_list_sources.append({name: value}) %}

      {%- else %}
        {%- do pkgs_list_version.append({name : value}) %}

      {%- endif %}
    {%- endfor %}

    {%- if pkgs_list_version %}
bootstrap_pkg_installed_pkgs_version:
  pkg.installed:
    - pkgs: {{ pkgs_list_version }}
    {%- endif %}

    {%- if pkgs_list_latest %}
bootstrap_pkg_installed_pkgs_latest:
  pkg.latest:
    - pkgs: {{ pkgs_list_latest }}
    {%- endif %}

    {%- if pkgs_list_sources %}
bootstrap_pkg_installed_sources:
  pkg.installed:
    - sources: {{ pkgs_list_sources }}
    {%- endif %}
{%- endif %}
