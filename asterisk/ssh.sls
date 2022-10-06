{% if pillar["asterisk"] is defined and pillar["сluster_asterisk"] is defined and "version" in pillar["asterisk"] %}
{% if pillar["сluster_asterisk"]["ssh_keys"] is defined %}

{% set user = pillar["asterisk"]["user"] %}
{% set group = pillar["asterisk"]["group"] %}
/var/lib/asterisk/.ssh:
  file.directory:
    - user: {{ user }}
    - group: {{ group }}
    - dir_mode: 700

ssh_keys_priv:
  file.managed:
    - name: /var/lib/asterisk/.ssh/{{ pillar["сluster_asterisk"]["ssh_keys"]["ssh_file"] }}
    - user: {{ user }}
    - group: {{ group }}
    - mode: 0600
    - contents: {{ pillar["сluster_asterisk"]["ssh_keys"]["priv"] | yaml_encode }}

ssh_keys_pub:
  file.managed:
    - name: /var/lib/asterisk/.ssh/{{ pillar["сluster_asterisk"]["ssh_keys"]["ssh_file"] }}.pub
    - user: {{ user }}
    - group: {{ group }}
    - mode: 0644
    - contents: {{ pillar["сluster_asterisk"]["ssh_keys"]["pub"] | yaml_encode }}

{%- endif %}
{%- endif %}