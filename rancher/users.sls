{% if pillar["rancher"] is defined and "users" in pillar["rancher"] %}

  {%- if grains["fqdn"] in pillar["rancher"]["command_hosts"] %}
    {%- for user in pillar["rancher"]["users"] %}
add_user_{{ loop.index }}:
  cmd.run:
    - name: >-
        curl -u "{{ pillar["rancher"]["bearer_token"] }}" -X POST -H 'Accept: application/json' -H 'Content-Type: application/json' -d '{"description":"{{ user["description"] }}", "me":false, "mustChangePassword":{{ 'true' if user["must_change_password"] else 'false' }}, "name":"{{ user["name"] }}", "password":"{{ user["password"] }}", "principalIds":[], "username":"{{ user["username"] }}"}' 'https://{{ pillar["rancher"]["cluster_domain"] }}/v3/users'
    {%- endfor %}
  {%- endif %}

{% endif %}
