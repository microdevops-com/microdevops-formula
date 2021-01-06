{% if pillar["bootstrap"] is defined and "root_password_hash" in pillar["bootstrap"] %}
bootstrap_root_password_hash:
  user.present:
    - name: root
    - password: {{ pillar["bootstrap"]["root_password_hash"] }}

{% endif %}
