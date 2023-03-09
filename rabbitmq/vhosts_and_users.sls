{% if pillar["rabbitmq"] is defined %}

  {%- for vhost in pillar["rabbitmq"].get("vhosts", []) %}
rabbit_vhost_{{ loop.index }}:
    {%- if vhost["present"] is defined and vhost["present"] %}
  rabbitmq_vhost.present:
    {%- elif vhost["absent"] is defined and vhost["absent"] %}
  rabbitmq_vhost.absent:
    {%- endif %}
    - name: '{{ vhost["name"] }}'
  {%- endfor %}

rabbit_user_guest_absent:
  rabbitmq_user.absent:
    - name: 'guest'

rabbit_user_admin_present:
  rabbitmq_user.present:
    - name: {{ pillar["rabbitmq"]["admin"]["name"] }}
    - password: {{ pillar["rabbitmq"]["admin"]["password"] }}
    - force: True
    - tags: administrator
    - perms:
        - '/':
            - '.*'
            - '.*'
            - '.*'
  {%- for vhost in pillar["rabbitmq"].get("vhosts", []) %}
    {%- if vhost["present"] is defined and vhost["present"] %}
        - '{{ vhost["name"] }}':
            - '.*'
            - '.*'
            - '.*'
    {%- endif %}
  {%- endfor %}

  {%- for user in pillar["rabbitmq"].get("users", []) %}
rabbit_user_{{ loop.index }}:
    {%- if user["present"] is defined and user["present"] %}
  rabbitmq_user.present:
    - name: '{{ user["name"] }}'
    - password: {{ user["password"] }}
    - force: True
    - tags: {{ user.get("tags", []) }}
    - perms: {{ user.get("perms", []) }}
    {%- elif user["absent"] is defined and user["absent"] %}
  rabbitmq_user.absent:
    - name: '{{ user["name"] }}'
    {%- endif %}
  {%- endfor %}

  {%- for policy in pillar["rabbitmq"].get("policies", []) %}
rabbit_policy_{{ loop.index }}:
    {%- if policy["present"] is defined and policy["present"] %}
  rabbitmq_policy.present:
    - name: {{ policy["name"] }}
    - pattern: '{{ policy["pattern"] }}'
    - definition: '{{ policy["definition"] }}'
    - priority: {{ policy["priority"] }}
    - vhost: '{{ policy["vhost"] }}'
    - apply_to: '{{ policy["apply_to"] }}'
    {%- elif policy["absent"] is defined and policy["absent"] %}
  rabbitmq_policy.absent:
    - name: {{ policy["name"] }}
    - vhost: '{{ policy["vhost"] }}'
    {%- endif %}
  {%- endfor %}

{% endif %}
