{%- if pillar["freeipa"] is defined %}
freeipa_data_dir:
  file.directory:
    - names:
      - /opt/freeipa/{{ pillar["freeipa"]["hostname"] }}/data
    - mode: 755
    - makedirs: True

  {%- if 'ipa_server_install_options' in pillar["freeipa"] %}
ipa_server_install_options:
  file.managed:
    - name: /opt/freeipa/{{ pillar["freeipa"]["hostname"] }}/data/ipa-server-install-options
    - contents_pillar: freeipa:ipa_server_install_options
  {%- endif %}

freeipa_image:
  cmd.run:
    - name: docker pull {{ pillar["freeipa"]["image"] }}

freeipa_container:
  docker_container.running:
    - name: freeipa-{{ pillar["freeipa"]["hostname"] }}
    - user: root
    - image: {{ pillar["freeipa"]["image"] }}
    - detach: True
    - restart_policy: unless-stopped
    - hostname: {{ pillar["freeipa"]["hostname"] }}
    - sysctl: {{ pillar["freeipa"]["sysctl"] }}
    - tmpfs:
      - /run: rw,noexec,nosuid,size=65536k
      - /tmp: rw,noexec,nosuid,size=65536k
    - cap_add: SYS_TIME
    - publish:
        - 0.0.0.0:53:53
        - 0.0.0.0:53:53/udp
        - 0.0.0.0:80:80
        - 0.0.0.0:88:88
        - 0.0.0.0:88:88/udp
        - 0.0.0.0:123:123/udp
        - 0.0.0.0:389:389
        - 0.0.0.0:443:443
        - 0.0.0.0:464:464
        - 0.0.0.0:464:464/udp
        - 0.0.0.0:636:636
    {%- if 'command' in pillar["freeipa"] %}
    - command: {{ pillar["freeipa"]["command"] }}
    {%- endif %}
    - binds:
        - /opt/freeipa/{{ pillar["freeipa"]["hostname"] }}/data:/data:rw
        - /sys/fs/cgroup:/sys/fs/cgroup:ro
  {%- if 'env_var' in pillar["freeipa"] %}
    - environment:
    {%- for var_key, var_val in pillar["freeipa"]["env_vars"].items() %}
        - {{ var_key }}: {{ var_val }}
    {%- endfor %}
  {%- endif %}
{%- endif %}
