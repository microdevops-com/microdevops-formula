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
    {%- if 'sysctls' in pillar["freeipa"] %}
    - sysctls:
      {%- for sysctl in pillar["freeipa"]["sysctls"] %}
        - {{ sysctl }}
      {%- endfor %}
    {%- endif %}
    - tmpfs:
      - /run: rw,noexec,nosuid,size=65536k
      - /tmp: rw,noexec,nosuid,size=65536k
    - cap_add: SYS_TIME
    {%- if 'extra_hosts' in pillar["freeipa"] %}
    - extra_hosts:
      {%- for extra_host in pillar["freeipa"]["extra_hosts"] %}
        - {{ extra_host }}
      {%- endfor %}
    {%- endif %}
    - publish:
        - {{ pillar["freeipa"]["ip"] }}:53:53
        - {{ pillar["freeipa"]["ip"] }}:53:53/udp
        - {{ pillar["freeipa"]["ip"] }}:80:80
        - {{ pillar["freeipa"]["ip"] }}:88:88
        - {{ pillar["freeipa"]["ip"] }}:88:88/udp
        - {{ pillar["freeipa"]["ip"] }}:123:123/udp
        - {{ pillar["freeipa"]["ip"] }}:389:389
        - {{ pillar["freeipa"]["ip"] }}:443:443
        - {{ pillar["freeipa"]["ip"] }}:464:464
        - {{ pillar["freeipa"]["ip"] }}:464:464/udp
        - {{ pillar["freeipa"]["ip"] }}:636:636
    {%- if 'command' in pillar["freeipa"] %}
    - command: {{ pillar["freeipa"]["command"] }}
    {%- endif %}
    {%- if 'dns' in pillar["freeipa"] %}
    - dns:
      {%- for address in pillar["freeipa"]["dns"] %}
        - {{ address }}
      {%- endfor %}
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

systemd-resolved drop-in:
  file.managed:
    - name: /etc/systemd/resolved.conf.d/freeipa.conf
    - makedirs: true
    - contents: |
        [Resolve]
        DNS={{ pillar["freeipa"]["ip"] }}
        Domains=~{{ pillar["freeipa"]["domain"] }}

systemd-resolved reload:
  cmd.run:
    - name: systemctl daemon-reload && systemctl restart systemd-resolved
    - onchanges:
      - file: /etc/systemd/resolved.conf.d/freeipa.conf
{%- endif %}