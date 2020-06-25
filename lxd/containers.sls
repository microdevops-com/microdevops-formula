{% if pillar['lxd'] is defined and pillar['lxd'] is not none and 'containers' in pillar['lxd'] %}
  {%- for container_name_dots, container_val in pillar['lxd']['containers'].items() %}
    {%- set a_loop = loop %}
    {%- if 'only' not in pillar['lxd'] or container_name_dots in pillar['lxd']['only'] %}
      {%- set container_name = container_name_dots|replace(".", "-") %}
lxd_launch_{{ loop.index }}:
  cmd.run:
    - name: 'lxc list | grep -q -e "| {{ container_name }} *|" || lxc launch {{ container_val['image'] }} {{ container_name }}'

      {%- if 'allow_stop_start' in pillar['lxd'] and pillar['lxd']['allow_stop_start'] %}
lxd_stop_{{ loop.index }}:
  cmd.run:
    - name: 'lxc stop {{ container_name }}'
      {%- endif %}

      {%- if 'devices' in container_val %}
        {%- for device_name, device_val in container_val['devices'].items() %}
          {%- set b_loop = loop %}
lxd_container_device_add_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: 'lxc config device list {{ container_name }} | grep -q -e "^{{ device_name }}$" || lxc config device add {{ container_name }} {{ device_name }} {{ device_val['type'] }}{% for device_param_key, device_param_val in device_val.items() %} {{ device_param_key }}={{ device_param_val }}{% endfor %}'

          {%- for device_param_key, device_param_val in device_val.items() %}
lxd_container_device_set_{{ a_loop.index }}_{{ b_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: 'lxc config device set {{ container_name }} {{ device_name }} {{ device_param_key }} {{ device_param_val }}'

          {%- endfor %}
        {%- endfor %}
      {%- endif %}

      {%- if 'config' in container_val %}
        {%- for config_key, config_val in container_val['config'].items() %}
lxd_config_set_{{ a_loop.index}}_{{ loop.index }}:
  cmd.run:
    - name: 'lxc config set {{ container_name }} {{ config_key }} {{ config_val }}'

        {%- endfor %}
      {%- endif %}

lxd_profile_assign_{{ loop.index }}:
  cmd.run:
    - name: 'lxc profile assign {{ container_name }} {% for profile in container_val['profiles'] %}{{ profile }}{{ "," if not loop.last else ""}}{% endfor %}'

      {%- if 'allow_stop_start' in pillar['lxd'] and pillar['lxd']['allow_stop_start'] %}
lxd_start_{{ loop.index }}:
  cmd.run:
    - name: 'lxc start {{ container_name }}'
      {%- endif %}

      {%- if 'bootstrap' in container_val %}
        {%- for bootstrap_item in container_val['bootstrap'] %}
          {%- set b_loop = loop %}
          {%- for bootstrap_script, bootstrap_params in bootstrap_item.items() %}
lxd_download_bootstrap_script_{{ a_loop.index}}_{{ b_loop.index}}_{{ loop.index }}:
  file.managed:
    - name: /tmp/lxd_bootstrap_{{ bootstrap_script }}
    - source: salt://lxd/bootstrap/{{ bootstrap_script }}
    - user: root
    - group: root
    - mode: 755

lxd_copy_bootstrap_script_{{ a_loop.index}}_{{ b_loop.index}}_{{ loop.index }}:
  cmd.run:
    - name: 'lxc file push /tmp/lxd_bootstrap_{{ bootstrap_script }} {{ container_name }}/etc/bootstrap_{{ bootstrap_script }}'

lxd_run_bootstrap_script_{{ a_loop.index}}_{{ b_loop.index}}_{{ loop.index }}:
  cmd.run:
    - name: 'lxc exec {{ container_name }} -- test ! -f /etc/bootstrap_{{ bootstrap_script }}.done && lxc exec {{ container_name }} -- /etc/bootstrap_{{ bootstrap_script }}{% for param in bootstrap_params %} "{{ container_name_dots if param == "__CONTAINER_NAME__" else param }}"{% endfor %} && lxc exec {{ container_name }} -- touch /etc/bootstrap_{{ bootstrap_script }}.done || true'

          {%- endfor %}
        {%- endfor %}
      {%- endif %}

    {%- endif %}
  {%- endfor %}
{% endif %}
