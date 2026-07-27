{% if pillar["openbao"] is defined and pillar["openbao"].get("unseal_keys") %}

{% set bao_addr = pillar["openbao"].get("env_vars", {}).get("BAO_ADDR", "https://127.0.0.1:8200") %}
{% set bao_cacert = pillar["openbao"].get("env_vars", {}).get("BAO_CACERT", "/opt/openbao/tls/tls.crt") %}

{% for key in pillar["openbao"]["unseal_keys"] %}
openbao_unseal_{{ loop.index }}:
  cmd.run:
    - name: bao operator unseal {{ key }}
    - shell: /bin/bash
    - env:
      - BAO_ADDR: "{{ bao_addr }}"
      - BAO_CACERT: "{{ bao_cacert }}"
    - onlyif: bao status | grep "Sealed" | grep -q "true"
{% endfor %}

{% endif %}
