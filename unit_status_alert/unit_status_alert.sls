{% if pillar['unit_status_alert'] is defined and pillar['unit_status_alert'] is not none %}
  {%- if grains['init'] == 'systemd' %}
    {%- if salt['file.directory_exists']('/opt/sysadmws/unit_status_alert') %}

      {%- if not salt['file.file_exists']('/etc/systemd/system/unit_system_alert@.service') %}
unit_status_alert_create_link:
  file.symlink:
    - name: '/etc/systemd/system/unit_status_alert@.service'
    - target: '/opt/sysadmws/unit_status_alert/unit_status_alert@.service'
      {%- endif %}

        {%- if pillar['unit_status_alert']['units'] is defined and pillar['unit_status_alert']['units'] is not none %}
          {%- for unit_name, unit_flag in pillar['unit_status_alert']['units'].items() %}
            {%- if unit_flag['enabled'] is defined and unit_flag['enabled'] is not none %}
              {%- if unit_flag['enabled'] %}
unit_status_alert_add_service_override:
  file.managed:
    - name: /etc/systemd/system/{{ unit_flag['prefix'] }}.service.d/unit_status_alert.conf
    - makedirs: True
    - user: root
    - group: root
    - mode: 644
    - contents: |
        [Unit]
        OnFailure=unit_status_alert@%p.service
              {%- else %}
unit_status_alert_remove_service_override:
  file.absent:
    - name: /etc/systemd/system/{{ unit_flag['prefix'] }}.service.d/unit_status_alert.conf
              {%- endif %}
            {%- endif %}
          {%- endfor %}
        {%- endif %}

unit_status_alert_reload_units:
  module.run:
    - name: service.systemctl_reload
    {%- endif %}
  {%- endif %}
{% endif %}
