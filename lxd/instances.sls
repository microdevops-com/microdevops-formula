{% if pillar["lxd"] is defined and "instances" in pillar["lxd"] %}
  {%- for instance_name_dots, instance_val in pillar["lxd"]["instances"].items() %}
    {%- set a_loop = loop %}
    {%- if "only" not in pillar["lxd"] or instance_name_dots in pillar["lxd"]["only"] %}
      {%- set instance_name = instance_name_dots|replace(".", "-") %}
lxd_init_{{ loop.index }}:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc list | grep -q -e "| {{ instance_name }} *|" || lxc init {% if "image" in instance_val %}{{ instance_val["image"] }}{% endif %} {{ instance_name }} {% if "vm" in instance_val and instance_val["vm"] %}--vm{% endif %} {% if "init_flags" in instance_val %}{{ instance_val["init_flags"] }}{% endif %}

      {%- if "allow_stop_start" in pillar["lxd"] and pillar["lxd"]["allow_stop_start"] %}
lxd_stop_{{ loop.index }}:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc list | grep -q -e "| {{ instance_name }} *| RUNNING |" && lxc stop {{ instance_name }} || true
      {%- endif %}

      {%- if "devices" in instance_val %}
        {%- for device_name, device_val in instance_val["devices"].items() %}
          {%- set b_loop = loop %}
lxd_instance_device_add_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc config device list {{ instance_name }} | grep -q -e "^{{ device_name }}$" || lxc config device add {{ instance_name }} {{ device_name }} {{ device_val["type"] }}{% for device_param_key, device_param_val in device_val.items() %} {{ device_param_key }}={{ device_param_val }}{% endfor %}

          {%- for device_param_key, device_param_val in device_val.items() %}
lxd_instance_device_set_{{ a_loop.index }}_{{ b_loop.index }}_{{ loop.index }}:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc config device set {{ instance_name }} {{ device_name }} {{ device_param_key }} {{ device_param_val }}

          {%- endfor %}
        {%- endfor %}
      {%- endif %}

      {%- if "config" in instance_val %}
        {%- for config_key, config_val in instance_val["config"].items() %}
lxd_config_set_{{ a_loop.index}}_{{ loop.index }}:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc config set {{ instance_name }} {{ config_key }} {{ config_val }}

        {%- endfor %}
      {%- endif %}

lxd_profile_assign_{{ loop.index }}:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc profile assign {{ instance_name }} {% for profile in instance_val["profiles"] %}{{ profile }}{{ "," if not loop.last else ""}}{% endfor %}

      {%- if "allow_stop_start" in pillar["lxd"] and pillar["lxd"]["allow_stop_start"] %}
lxd_start_{{ loop.index }}:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc start {{ instance_name }}

lxd_wait_{{ loop.index }}:
  cmd.run:
    - prepend_path: /snap/bin
    - name: timeout 30s bash -c "until lxc exec {{ instance_name }} true; do sleep 1; done"
      {%- endif %}

      {%- if "bootstrap" in instance_val %}
        {%- for bootstrap_item in instance_val["bootstrap"] %}
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
    - prepend_path: /snap/bin
    - name: lxc file push /tmp/lxd_bootstrap_{{ bootstrap_script }} {{ instance_name }}/etc/bootstrap_{{ bootstrap_script }}

lxd_run_bootstrap_script_{{ a_loop.index}}_{{ b_loop.index}}_{{ loop.index }}:
  cmd.run:
    - prepend_path: /snap/bin
    - name: lxc exec {{ instance_name }} -- test ! -f /etc/bootstrap_{{ bootstrap_script }}.done && lxc exec {{ instance_name }} -- /etc/bootstrap_{{ bootstrap_script }}{% for param in bootstrap_params %} "{{ instance_name_dots if param == "__INSTANCE_NAME__" else param }}"{% endfor %} && lxc exec {{ instance_name }} -- touch /etc/bootstrap_{{ bootstrap_script }}.done || true

          {%- endfor %}
        {%- endfor %}
      {%- endif %}

    {%- endif %}
  {%- endfor %}
{% endif %}
