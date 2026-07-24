{% if pillar["openbao"] is defined and pillar["openbao"].get("audit") %}

{% set audit_logfile = pillar["openbao"]["audit"].get("logfile", "/var/log/openbao_audit.log") %}
{% set config_dir = pillar["openbao"].get("config_dir", "/etc/openbao") %}
{% set audit_path = pillar["openbao"]["audit"].get("path", "file") %}

{% if pillar["openbao"]["audit"].get("enable", False) %}

openbao_audit_file_create:
  file.managed:
    - name: {{ audit_logfile }}
    - user: openbao
    - group: openbao
    - mode: 0640
    - makedirs: True
    - replace: False

openbao_audit_config:
  file.managed:
    - name: {{ config_dir }}/audit.hcl
    - user: openbao
    - group: openbao
    - mode: 0640
    - contents: |
        audit "file" "{{ audit_path }}" {
          description = "OpenBao file audit device"
          options {
            file_path = "{{ audit_logfile }}"
          }
        }
    - require:
      - file: openbao_audit_file_create

openbao_audit_reload:
  cmd.run:
    - name: systemctl reload openbao || systemctl restart openbao
    - onchanges:
      - file: openbao_audit_config
    - require:
      - file: openbao_audit_config

{% else %}

openbao_audit_config_absent:
  file.absent:
    - name: {{ config_dir }}/audit.hcl

openbao_audit_reload:
  cmd.run:
    - name: systemctl reload openbao || systemctl restart openbao
    - onchanges:
      - file: openbao_audit_config_absent

{% endif %}

{% endif %}
