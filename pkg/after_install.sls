{% set PKG_WHEN = 'PKG_AFTER_INSTALL' %}
{% include 'pkg/pkg.jinja' with context %}
