{% set keepalived = pillar.get("keepalived", none) %}
{% if keepalived %}
  {% if keepalived.get("config", none) %}
    {% if not (pillar.get("keepalived_legacy", false) or keepalived.get("version", "") == "legacy" ) %}
      {{ raise("LEGACY WARNING! See updates in 'https://github.com/microdevops-com/microdevops-formula/tree/master/keepalived'. Add \"pillar='{keepalived_legacy: true}'\" or set 'version: legacy' in pillar to omit this warning.") }}
    {% endif %}
    {% include "keepalived/legacy/init.sls" with context %}
  {% else %}
    {% set version = keepalived.setdefault("version", "v20241114") %}
    {% include "keepalived/" ~ version ~ "/init.sls" with context %}
  {% endif %}
{% endif %}
