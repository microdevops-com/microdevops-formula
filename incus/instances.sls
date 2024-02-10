{% if pillar["incus"] is defined and "instances" in pillar["incus"] %}
  {%- for instance_name_dots, instance_val in pillar["incus"]["instances"].items() %}
    {%- set a_loop = loop %}
    {%- if "only" not in pillar["incus"] or instance_name_dots in pillar["incus"]["only"] %}
      {%- set instance_name = instance_name_dots|replace(".", "-") %}
incus_init_{{ loop.index }}:
  cmd.run:
    - name: incus list | grep -q -e "| {{ instance_name }} *|" || incus init {% if "image" in instance_val %}{{ instance_val["image"] }}{% endif %} {{ instance_name }} {% if "vm" in instance_val and instance_val["vm"] %}--vm{% endif %} {% if "init_flags" in instance_val %}{{ instance_val["init_flags"] }}{% endif %}

      {%- if "allow_stop_start" in pillar["incus"] and pillar["incus"]["allow_stop_start"] %}
incus_stop_{{ loop.index }}:
  cmd.run:
    - name: incus list | grep -q -e "| {{ instance_name }} *| RUNNING |" && incus stop {{ instance_name }} || true
      {%- endif %}

      {%- if "devices" in instance_val %}
        {%- for device_name, device_val in instance_val["devices"].items() %}
          {%- set b_loop = loop %}
incus_instance_device_add_{{ a_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: incus config device list {{ instance_name }} | grep -q -e "^{{ device_name }}$" || incus config device add {{ instance_name }} {{ device_name }} {{ device_val["type"] }}{% for device_param_key, device_param_val in device_val.items() %} {{ device_param_key }}={{ device_param_val }}{% endfor %}

          {%- for device_param_key, device_param_val in device_val.items() %}
incus_instance_device_set_{{ a_loop.index }}_{{ b_loop.index }}_{{ loop.index }}:
  cmd.run:
    - name: incus config device set {{ instance_name }} {{ device_name }} {{ device_param_key }} {{ device_param_val }}

          {%- endfor %}
        {%- endfor %}
      {%- endif %}

      {%- if "config" in instance_val %}
        {%- for config_key, config_val in instance_val["config"].items() %}
incus_config_set_{{ a_loop.index}}_{{ loop.index }}:
  cmd.run:
    - name: incus config set {{ instance_name }} {{ config_key }} {{ config_val }}

        {%- endfor %}
      {%- endif %}

incus_profile_assign_{{ loop.index }}:
  cmd.run:
    - name: incus profile assign {{ instance_name }} {% for profile in instance_val["profiles"] %}{{ profile }}{{ "," if not loop.last else ""}}{% endfor %}

      {%- if "allow_stop_start" in pillar["incus"] and pillar["incus"]["allow_stop_start"] %}
incus_start_{{ loop.index }}:
  cmd.run:
    - name: incus start {{ instance_name }}

        {%- if not ("skip_wait_exec_true" in instance_val and instance_val["skip_wait_exec_true"]) %}
incus_wait_{{ loop.index }}:
  cmd.run:
    - name: timeout 30s bash -c "until incus exec {{ instance_name }} true; do sleep 1; done"

        {%- endif %}

      {%- endif %}

      {%- if "bootstrap" in instance_val %}
        {%- for bootstrap_item in instance_val["bootstrap"] %}
          {%- set b_loop = loop %}
          {%- for bootstrap_script, bootstrap_params in bootstrap_item.items() %}
incus_download_bootstrap_script_{{ a_loop.index}}_{{ b_loop.index}}_{{ loop.index }}:
  file.managed:
    - name: /tmp/incus_bootstrap_{{ bootstrap_script }}
    - source: salt://incus/bootstrap/{{ bootstrap_script }}
    - user: root
    - group: root
    - mode: 755

incus_copy_bootstrap_script_{{ a_loop.index}}_{{ b_loop.index}}_{{ loop.index }}:
  cmd.run:
    - name: incus file push /tmp/incus_bootstrap_{{ bootstrap_script }} {{ instance_name }}/etc/bootstrap_{{ bootstrap_script }}

incus_run_bootstrap_script_{{ a_loop.index}}_{{ b_loop.index}}_{{ loop.index }}:
  cmd.run:
    - name: incus exec {{ instance_name }} -- /etc/bootstrap_{{ bootstrap_script }}{% for param in bootstrap_params %} "{{ instance_name_dots if param == "__INSTANCE_NAME__" else param }}"{% endfor %}

          {%- endfor %}
        {%- endfor %}
      {%- endif %}
    {%- endif %}
  {%- endfor %}
{% endif %}
